import SwiftUI
import CoreBluetooth

struct SettingsView: View {
    @Environment(NavigationManager.self) private var nav
    @Environment(BluetoothManager.self) private var ble
    @Environment(HealthManager.self) private var health
    
    @State private var showingLogs = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // Device Section
                        settingsSection("Appareil Bluetooth") {
                            VStack(spacing: 12) {
                                if let peripheral = (ble.effectiveConnectionState == .connected ? "Connecté" : "Non connecté") {
                                    HStack {
                                        Image(systemName: "cpu")
                                            .foregroundStyle(Color.neonCyan)
                                        Text(ble.effectiveConnectionState.rawValue)
                                            .font(.headline)
                                        Spacer()
                                        if ble.effectiveConnectionState == .connected {
                                            Button("Déconnecter") {
                                                ble.disconnect()
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                        }
                                    }
                                }
                                
                                Divider().background(.white.opacity(0.1))
                                
                                Button {
                                    ble.startScanning()
                                } label: {
                                    Label("Rechercher des appareils", systemImage: "magnifyingglass")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.neonCyan)
                                
                                if !ble.discoveredPeripherals.isEmpty {
                                    ForEach(ble.discoveredPeripherals, id: \.identifier) { p in
                                        Button {
                                            ble.connect(to: p)
                                        } label: {
                                            HStack {
                                                Text(p.name ?? "Inconnu")
                                                Spacer()
                                                if ble.effectiveConnectionState == .connected {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(.green)
                                                }
                                            }
                                            .padding(10)
                                            .background(.white.opacity(0.05))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        
                        // Apple Watch Test Section
                        settingsSection("Test Apple Watch") {
                            VStack(spacing: 15) {
                                Text("La fréquence cardiaque live remonte depuis l’app Apple Watch compagnon. Autorise Santé sur la montre, puis lance le test depuis l’iPhone.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Fréquence Monitorée")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text("\(health.watchHeartRate) BPM")
                                            .font(.system(size: 32, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color.neonRed)
                                    }
                                    Spacer()
                                    
                                    Button {
                                        if health.isWorkoutActive {
                                            print("[Settings] Clic sur 'Arrêter le Test'")
                                            Task { await health.endWorkout() }
                                        } else {
                                            print("[Settings] Clic sur 'Lancer le Test'")
                                            Task { await health.startWorkout() }
                                        }
                                    } label: {
                                        Text(health.isWorkoutActive ? "Arrêter le Test" : "Lancer le Test")
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(health.isWorkoutActive ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                                            .foregroundStyle(health.isWorkoutActive ? .red : .blue)
                                            .clipShape(Capsule())
                                    }
                                }

                                if let message = health.liveHeartRateStatusMessage {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                        Text(message)
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.orange.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        
                        // Debug Section
                        settingsSection("Debug & Logs") {
                            VStack(spacing: 14) {
                                // Force connected toggle
                                HStack(spacing: 12) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundStyle(.orange)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Forcer l'état connecté")
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                        Text("Simule le BLE sans hardware")
                                            .font(.caption2)
                                            .foregroundStyle(.orange.opacity(0.8))
                                    }

                                    Spacer()

                                    Toggle("", isOn: Binding(
                                        get: { ble.isDebugForceConnected },
                                        set: { ble.isDebugForceConnected = $0 }
                                    ))
                                    .labelsHidden()
                                    .tint(.orange)
                                }

                                if ble.isDebugForceConnected {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                        Text("Mode debug actif — l'état connecté est simulé")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.orange.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }

                                Divider().background(.white.opacity(0.1))

                                Button {
                                    showingLogs = true
                                } label: {
                                    HStack {
                                        Label("Détail des trames Bluetooth", systemImage: "terminal")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .animation(.spring(response: 0.3), value: ble.isDebugForceConnected)
                        }
                        
                        // App Section
                        settingsSection("Application") {
                            VStack(spacing: 12) {
                                Button {
                                    nav.resetOnboarding()
                                } label: {
                                    Label("Relancer l'onboarding", systemImage: "arrow.counterclockwise")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.neonPurple)
                                
                                Link(destination: URL(string: "https://github.com/badwulf/OpenCareFitness")!) {
                                    Label("Code Source (GitHub)", systemImage: "link")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                        
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)

            .sheet(isPresented: $showingLogs) {
                BluetoothLogsView(logs: ble.frameLogs)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            
            VStack {
                content()
            }
            .padding(16)
            .glassPanel(cornerRadius: 20)
        }
    }
}

// MARK: - Logs View

struct BluetoothLogsView: View {
    let logs: [FrameLog]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                List(logs) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        let directionIcon = log.direction == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
                        let directionColor = log.direction == .sent ? Color.neonPurple : Color.neonCyan
                        let directionLabel = log.direction == .sent ? "TX" : "RX"
                        let bgColor = log.direction == .sent ? Color.neonPurple.opacity(0.2) : Color.neonCyan.opacity(0.2)

                        HStack {
                            Image(systemName: directionIcon)
                                .foregroundStyle(directionColor)
                            Text(log.timestamp, format: .dateTime.hour().minute().second())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(directionLabel)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 4)
                                .background(bgColor)
                                .foregroundStyle(directionColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        Text(log.hexString)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                .listStyle(.plain)
            }
            .navigationTitle("Logs des trames")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Previews

#Preview("Settings") {
    SettingsView()
        .environment(NavigationManager())
        .environment(BluetoothManager())
        .environment(HealthManager())
}

#Preview("Bluetooth Logs") {
    let mockLogs: [FrameLog] = [
        FrameLog(data: Data([0x20, 0x01, 0x05, 0x00, 0x26]), direction: .sent),
        FrameLog(data: Data([0x20, 0x02, 0x10, 0x00, 0x32, 0x00, 0x40, 0x00, 0x00, 0x05, 0x00, 0x00]), direction: .received),
        FrameLog(data: Data([0x40, 0x00, 0x16, 0x0A, 0x60]), direction: .sent)
    ]
    return BluetoothLogsView(logs: mockLogs)
}
