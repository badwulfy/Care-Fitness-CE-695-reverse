//
//  BluetoothManager.swift
//  opencarefitness
//
//  Manages BLE connection to the Care Fitness CE-695.
//  Handles scanning, connecting, init handshake, keep-alive ping,
//  and telemetry parsing.
//

import Foundation
import CoreBluetooth

// MARK: - Constants

private enum BLEConstants {
    static let serviceUUID      = CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")
    static let notifyCharUUID   = CBUUID(string: "0000FFF1-0000-1000-8000-00805F9B34FB")
    static let writeCharUUID    = CBUUID(string: "0000FFF2-0000-1000-8000-00805F9B34FB")
    static let batteryService   = CBUUID(string: "180F")
    static let batteryCharUUID  = CBUUID(string: "2A19")
    static let namePrefix       = "CARE"
    static let namePrefixes     = ["Care", "iConsole", "CE-695", "Kinomap"]
    static let initCommand: [UInt8] = [0x40, 0x00, 0x16, 0x0A, 0x60]
    static let pingInterval: TimeInterval = 1.0
    static let disconnectTimeout: TimeInterval = 6.0
}

private enum BLEStorageKeys {
    static let preferredPeripheralID = "preferredPeripheralID"
    static let preferredPeripheralName = "preferredPeripheralName"
}

// MARK: - Connection State

enum BLEConnectionState: String {
    case disconnected = "Déconnecté"
    case scanning     = "Recherche…"
    case connecting   = "Connexion…"
    case initializing = "Initialisation…"
    case connected    = "Connecté"
    case error        = "Erreur"
}

// MARK: - BluetoothManager

@Observable
final class BluetoothManager: NSObject {

    // Public state
    var connectionState: BLEConnectionState = .disconnected
    var isBluetoothPoweredOn: Bool = false
    var batteryLevel: Int?
    var telemetry = Telemetry()
    var lastSentResistanceLevel: Int = 1
    var preferredPeripheralIdentifier: UUID? {
        didSet {
            UserDefaults.standard.set(preferredPeripheralIdentifier?.uuidString, forKey: BLEStorageKeys.preferredPeripheralID)
        }
    }
    var preferredPeripheralName: String? {
        didSet {
            UserDefaults.standard.set(preferredPeripheralName, forKey: BLEStorageKeys.preferredPeripheralName)
        }
    }
    var connectedPeripheralIdentifier: UUID?
    var connectedPeripheralName: String?

    // Debug override : force l'état connecté sans hardware
    var isDebugForceConnected: Bool = false

    /// Source de vérité unique pour l'état de connexion (prend en compte le override debug)
    var effectiveConnectionState: BLEConnectionState {
        isDebugForceConnected ? .connected : connectionState
    }
    
    // Discovery & Logging
    var discoveredPeripherals: [CBPeripheral] = []
    var frameLogs: [FrameLog] = []
    private let maxLogs = 100

    // Target resistance level (1–32), set externally
    var targetResistance: Int = 1

    // Private BLE
    private var centralManager: CBCentralManager?
    
    // State to show "Autoriser" button if not yet requested
    var hasRequestedAuthorization: Bool = false
    private var peripheral: CBPeripheral?
    private var notifyChar: CBCharacteristic?
    private var writeChar: CBCharacteristic?

    // Keep-alive task
    private var keepAliveTask: Task<Void, Never>?
    private var disconnectWatchTask: Task<Void, Never>?
    private var isAttemptingPreferredReconnect = false

    override init() {
        if let rawIdentifier = UserDefaults.standard.string(forKey: BLEStorageKeys.preferredPeripheralID) {
            preferredPeripheralIdentifier = UUID(uuidString: rawIdentifier)
        }
        preferredPeripheralName = UserDefaults.standard.string(forKey: BLEStorageKeys.preferredPeripheralName)
        super.init()
        // CBCentralManager is now initialized lazily to avoid premature permission dialogs.
    }

    // MARK: - Public API

    func requestAuthorization() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
            hasRequestedAuthorization = true
        }
    }

    func startScanning() {
        requestAuthorization()
        guard let centralManager = centralManager, centralManager.state == .poweredOn else {
            print("[BLE] Scanner ignoré : le Bluetooth n'est pas activé.")
            return
        }
        print("[BLE] Début du scan des périphériques...")
        connectionState = .scanning
        discoveredPeripherals.removeAll()
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func connect(to peripheral: CBPeripheral) {
        centralManager?.stopScan()
        preferredPeripheralIdentifier = peripheral.identifier
        preferredPeripheralName = peripheral.name
        isAttemptingPreferredReconnect = false
        isUserDisconnected = false
        self.peripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        print("[BLE] Tentative de connexion à \(peripheral.name ?? "Inconnu")...")
        centralManager?.connect(peripheral, options: nil)
    }

    func disconnect() {
        print("[BLE] Demande de déconnexion volontaire")
        isUserDisconnected = true
        if let p = peripheral {
            if let c = notifyChar { p.setNotifyValue(false, for: c) }
            centralManager?.cancelPeripheralConnection(p)
        }
        clearConnection()
        connectionState = .disconnected
    }

    /// User explicitly disconnected → don't auto-rescan after disconnect.
    /// Reset on `connect()` / `clearPreferredPeripheral()`.
    private var isUserDisconnected = false

    /// Tears down all per-connection state. Doesn't touch user-intent flags
    /// (preferredPeripheral, autoReconnectEnabled).
    private func clearConnection() {
        keepAliveTask?.cancel(); keepAliveTask = nil
        disconnectWatchTask?.cancel(); disconnectWatchTask = nil
        peripheral = nil
        notifyChar = nil
        writeChar = nil
        connectedPeripheralIdentifier = nil
        connectedPeripheralName = nil
        telemetry.isReceiving = false
        isAttemptingPreferredReconnect = false
    }

    func clearPreferredPeripheral() {
        preferredPeripheralIdentifier = nil
        preferredPeripheralName = nil
        isAttemptingPreferredReconnect = false
        isUserDisconnected = true
    }

    // MARK: - Resistance Command

    /// Build resistance command: [0x20, 0x01, LVL, 0x00, CHK]
    static func resistanceCommand(level: Int) -> Data {
        let lvl = UInt8(max(1, min(32, level)))
        var msg: [UInt8] = [0x20, 0x01, lvl, 0x00]
        let chk = msg.reduce(0, &+) & 0xFF
        msg.append(chk)
        return Data(msg)
    }

    private func logFrame(_ data: Data, direction: FrameDirection) {
        let log = FrameLog(data: data, direction: direction)
        DispatchQueue.main.async {
            self.frameLogs.insert(log, at: 0)
            if self.frameLogs.count > self.maxLogs {
                self.frameLogs.removeLast()
            }
        }
    }

    /// Incline percentage (0–15%) → machine resistance level (12–32).
    static func inclineToResistance(_ incline: Double) -> Int {
        let clamped = min(15.0, max(0.0, incline))
        return Int(round(12.0 + (clamped * 20.0 / 15.0)))
    }

    /// Resistance level (12–32) → incline percentage (0–15%).
    static func resistanceToIncline(_ level: Int) -> Double {
        let clamped = min(32, max(12, level))
        return Double(clamped - 12) * 15.0 / 20.0
    }

    private func sendResistance() {
        guard let writeChar, let peripheral else { return }
        let level = max(1, min(32, targetResistance))
        lastSentResistanceLevel = level
        let cmd = Self.resistanceCommand(level: level)
        logFrame(cmd, direction: .sent)
        peripheral.writeValue(cmd, for: writeChar, type: .withoutResponse)
    }

    // MARK: - Keep-alive loop

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.sendResistance()
                
                // Ping every 3s when idle (resistance = 1), otherwise 1s
                let interval: TimeInterval = self.targetResistance <= 1 ? 3.0 : 1.0
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func startDisconnectWatch() {
        disconnectWatchTask?.cancel()
        disconnectWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.0))
                guard let self else { return }
                if self.connectionState == .connected,
                   Date().timeIntervalSince(self.telemetry.lastUpdate) > BLEConstants.disconnectTimeout {
                    self.telemetry.isReceiving = false
                }
            }
        }
    }

    // MARK: - Init handshake

    private func sendInit() {
        guard let writeChar, let peripheral else { return }
        let cmd = Data(BLEConstants.initCommand)
        logFrame(cmd, direction: .sent)
        peripheral.writeValue(cmd, for: writeChar, type: .withoutResponse)
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothPoweredOn = (central.state == .poweredOn)
        print("[BLE] Etat du gestionnaire Bluetooth (CBCentralManager) : \(central.state.rawValue)")
        if central.state == .poweredOn, connectionState == .disconnected, !isUserDisconnected {
            startScanning()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard let name = peripheral.name else { return }
        let matches = BLEConstants.namePrefixes.contains { name.localizedCaseInsensitiveContains($0) }
        guard matches else { return }

        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
        }
        
        print("[BLE] 🔎 Appareil trouvé : \(name) [\(peripheral.identifier)] avec RSSI \(RSSI)")

        guard connectionState == .scanning,
              self.peripheral == nil,
              !isAttemptingPreferredReconnect,
              let preferredPeripheralIdentifier,
              preferredPeripheralIdentifier == peripheral.identifier else {
            return
        }

        isAttemptingPreferredReconnect = true
        connect(to: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BLE] ✅ Connecté au périphérique ! Découverte des services...")
        isAttemptingPreferredReconnect = false
        connectedPeripheralIdentifier = peripheral.identifier
        connectedPeripheralName = peripheral.name
        connectionState = .initializing
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print("[BLE] ⚠️ Déconnecté de \(peripheral.name ?? "Inconnu"). Erreur: \(error?.localizedDescription ?? "Aucune")")
        clearConnection()
        // Unexpected drop while we still own a preferred device → rescan; the
        // existing didDiscover path will auto-reconnect to it.
        if !isUserDisconnected, preferredPeripheralIdentifier != nil,
           centralManager?.state == .poweredOn {
            startScanning()
        } else {
            connectionState = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print("[BLE] ❌ Échec de la connexion à \(peripheral.name ?? "Inconnu"). Erreur: \(error?.localizedDescription ?? "Aucune")")
        isAttemptingPreferredReconnect = false
        if !isUserDisconnected, preferredPeripheralIdentifier != nil {
            startScanning()
        } else {
            connectionState = .error
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
             print("[BLE] Aucun service découvert.")
             return
        }
        print("[BLE] Services découverts :")
        for service in services {
            print("  - Service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let chars = service.characteristics else { return }
        
        print("[BLE]   Caractéristiques pour le service \(service.uuid) :")

        for char in chars {
            let props = char.properties
            print("    * Char \(char.uuid) (Propriétés: \(props))")

            // Skip Battery characteristic (2A19)
            if char.uuid.uuidString.uppercased() == BLEConstants.batteryCharUUID.uuidString.uppercased() {
                print("[BLE]     -> Tentative lecture batterie")
                peripheral.readValue(for: char)
                continue
            }

            // If it has notify or indicate, use for notify
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                print("[BLE]     -> Assigné en Notify")
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
            }

            // If it has write or writeWithoutResponse, use for write
            if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                print("[BLE]     -> Assigné en Write")
                writeChar = char
            }
        }

        // Once we have both characteristics, proceed
        if notifyChar != nil && writeChar != nil && connectionState == .initializing {
            print("[BLE] ✅ Caractéristiques configurées (Notify: \(notifyChar!.uuid), Write: \(writeChar!.uuid)). Démarrage boucle...")
            self.connectionState = .connected
            self.startKeepAlive()
            self.startDisconnectWatch()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }

        // Battery level
        if characteristic.uuid == BLEConstants.batteryCharUUID, let first = data.first {
            print("[BLE] 🔋 Batterie reçue: \(first)%")
            batteryLevel = Int(first)
            return
        }

        // Telemetry frame
        if data.count >= 12 && data[0] == 0x20 {
            logFrame(data, direction: .received)
            telemetry.parse(data: data)
        } else {
            logFrame(data, direction: .received)
            print("[BLE] [REÇU] Trame inconnue ou configuration (\(data.count) bytes) : \(data.map { String(format:"%02x", $0) }.joined())")
        }
    }
}

// MARK: - Logging helper

enum FrameDirection {
    case sent, received
}

struct FrameLog: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let data: Data
    let direction: FrameDirection
    
    var hexString: String {
        data.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
