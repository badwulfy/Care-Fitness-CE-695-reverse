import SwiftUI
import CoreBluetooth

struct BluetoothSelectionPage: View {
    var ble: BluetoothManager
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
                    .neonGlow(Color.neonCyan, radius: 15)
                
                Text("Votre Appareil")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 16) {
                if !ble.hasRequestedAuthorization {
                    VStack(spacing: 16) {
                        Text("Autorisation requise")
                            .font(.headline)
                        Text("Nous avons besoin du Bluetooth pour communiquer avec votre elliptique.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            ble.requestAuthorization()
                            // Petit délai pour laisser le système afficher l'alerte
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if ble.isBluetoothPoweredOn {
                                    ble.startScanning()
                                }
                            }
                        } label: {
                            Text("Autoriser le Bluetooth")
                                .font(.headline)
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                } else if !ble.isBluetoothPoweredOn {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(.yellow)
                        Text("Bluetooth désactivé")
                            .font(.headline)
                        Text("Activez le Bluetooth dans les réglages pour continuer.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.yellow.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                } else {
                    Text("Sélectionnez votre vélo elliptique compatible.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                ScrollView {
                    VStack(spacing: 10) {
                        if ble.discoveredPeripherals.isEmpty && ble.isBluetoothPoweredOn {
                            ProgressView()
                                .tint(.white)
                                .padding()
                            Text("Recherche...")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        
                        ForEach(ble.discoveredPeripherals, id: \.identifier) { peripheral in
                            Button {
                                ble.connect(to: peripheral)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(peripheral.name ?? "Inconnu")
                                            .font(.headline)
                                        Text(peripheral.identifier.uuidString.prefix(8))
                                            .font(.system(size: 10, design: .monospaced))
                                            .opacity(0.5)
                                    }
                                    Spacer()
                                    if ble.connectionState == .connected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.neonCyan)
                                    }
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
            .padding(20)
            .glassPanel(cornerRadius: 30)
            
            Button {
                ble.startScanning()
            } label: {
                Label("Scanner à nouveau", systemImage: "arrow.clockwise")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassPanel(cornerRadius: 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 30)
        .padding(.top, 30)
        .padding(.bottom, 140)
        .onAppear {
            if ble.hasRequestedAuthorization {
                ble.startScanning()
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        BluetoothSelectionPage(ble: BluetoothManager())
    }
}
