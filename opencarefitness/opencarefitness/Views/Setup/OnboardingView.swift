import SwiftUI
import CoreBluetooth
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Onboarding Page Enum

private enum OnboardingPage: Int, CaseIterable {
    case welcome   = 0
    case health    = 1
    case bluetooth = 2
    case finale    = 3

    var isSkippable: Bool {
        self == .health || self == .bluetooth
    }
}

struct OnboardingView: View {
    @Environment(NavigationManager.self) private var nav
    @Environment(HealthManager.self) private var health
    @Environment(BluetoothManager.self) private var ble

    @State private var currentPage: OnboardingPage = .welcome
    @State private var healthAuthorized = false

    private let pageColors: [Color] = [
        Color(hue: 0.78, saturation: 0.55, brightness: 0.18), // violet
        Color(hue: 0.62, saturation: 0.60, brightness: 0.20), // bleu nuit
        Color(hue: 0.52, saturation: 0.65, brightness: 0.18), // cyan nuit
        Color(hue: 0.40, saturation: 0.60, brightness: 0.16), // vert nuit
    ]

    var body: some View {
        ZStack {
            // Background animé qui change de couleur selon la page
            pageColors[currentPage.rawValue]
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: currentPage)

            TabView(selection: $currentPage) {
                WelcomePage()
                    .tag(OnboardingPage.welcome)
                HealthPermissionPage(isAuthorized: $healthAuthorized, requestAction: requestHealth)
                    .tag(OnboardingPage.health)
                BluetoothSelectionPage(ble: ble)
                    .tag(OnboardingPage.bluetooth)
                FinalPage()
                    .tag(OnboardingPage.finale)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Contrôles navigation en bas
            VStack {
                Spacer()
                HStack {
                    // Indicateurs de page
                    HStack(spacing: 8) {
                        ForEach(OnboardingPage.allCases, id: \.self) { page in
                            Capsule()
                                .fill(page == currentPage ? Color.white : Color.white.opacity(0.35))
                                .frame(width: page == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }

                    Spacer()

                    // Bouton unique dynamique (Nav / Passer / Démarrer)
                    Button { advance() } label: {
                        Group {
                            if currentPage == .finale {
                                Text("Démarrer")
                                    .padding(.horizontal, 28)
                            } else if currentPage == .health && !healthAuthorized {
                                Text("Passer")
                                    .padding(.horizontal, 20)
                            } else if currentPage == .bluetooth && ble.connectionState != .connected {
                                Text("Passer")
                                    .padding(.horizontal, 20)
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 20, weight: .bold))
                            }
                        }
                        .foregroundStyle(pageColors[currentPage.rawValue])
                        .frame(height: 56)
                        .frame(minWidth: 56)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: healthAuthorized)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: ble.connectionState)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { syncHealthStatus() }
        .onChange(of: currentPage) { _, page in
            if page == .health { syncHealthStatus() }
        }
    }

    private func advance() {
        if currentPage == .finale {
            nav.completeOnboarding()
        } else if let next = OnboardingPage(rawValue: currentPage.rawValue + 1) {
            withAnimation { currentPage = next }
        }
    }

    private func requestHealth() {
        Task {
            await health.requestAuthorization()
            healthAuthorized = health.isAuthorized
        }
    }

    private func syncHealthStatus() {
        healthAuthorized = health.isAuthorized
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 20) {
                Image(systemName: "figure.elliptical")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                    .neonGlow(Color.neonPurple, radius: 20)
                
                Text("OpenCare Fitness")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white)
            }
            
            Text("L'application moderne pour votre elliptique Care Fitness CE-695.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 30)
                .padding(.vertical, 24)
                .glassPanel(cornerRadius: 30)
        }
        .padding(30)
    }
}

private struct HealthPermissionPage: View {
    @Binding var isAuthorized: Bool
    var requestAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 80))
                .foregroundStyle(.white)
                .neonGlow(Color.neonBlue, radius: 15)

            VStack(spacing: 16) {
                Text("Apple Santé")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text("Synchronisez vos entraînements et récupérez votre fréquence cardiaque depuis l'Apple Watch.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(24)
            .glassPanel(cornerRadius: 30)

            if isAuthorized {
                Label("Autorisé", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .glassPanel(cornerRadius: 20)
                    .foregroundStyle(.green)
            } else {
                VStack(spacing: 12) {
                    Button(action: requestAction) {
                        Text("Autoriser l'accès")
                            .font(.headline)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                            .background(.white)
                            .foregroundStyle(Color.neonBlue)
                            .clipShape(Capsule())
                    }

                    // Si déjà refusé, proposer d'ouvrir les réglages Santé
                    Button {
                        openHealthSettings()
                    } label: {
                        Label("Ouvrir les réglages Santé", systemImage: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 30)
            }
        }
        .padding(30)
    }

    private func openHealthSettings() {
        #if canImport(UIKit)
        // Ouvre les réglages de l'app (section Santé & confidentialité)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

private struct BluetoothSelectionPage: View {
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
                if !ble.isBluetoothPoweredOn {
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
            ble.startScanning()
        }
    }
}

private struct FinalPage: View {
    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 180, height: 180)
                Image(systemName: "sparkles")
                    .font(.system(size: 100))
                    .foregroundStyle(.white)
                    .neonGlow(Color.neonGreen, radius: 25)
            }
            
            VStack(spacing: 16) {
                Text("Vous êtes prêt !")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Votre configuration est terminée. Profitez de votre séance.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(24)
            .glassPanel(cornerRadius: 30)
        }
        .padding(30)
    }
}

// MARK: - Previews

#Preview("Onboarding") {
    OnboardingView()
        .environment(NavigationManager())
        .environment(HealthManager())
        .environment(BluetoothManager())
}

#Preview("Onboarding — Light Mode") {
    OnboardingView()
        .environment(NavigationManager())
        .environment(HealthManager())
        .environment(BluetoothManager())
        .preferredColorScheme(.light)
}
