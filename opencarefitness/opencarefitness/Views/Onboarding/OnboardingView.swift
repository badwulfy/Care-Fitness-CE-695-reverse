import SwiftUI

// MARK: - Onboarding Page Enum

enum OnboardingPage: Int, CaseIterable {
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
        Task {
            await health.checkAuthorization()
            healthAuthorized = health.isAuthorized
        }
    }
}

// MARK: - Previews

#Preview("Onboarding") {
    OnboardingView()
        .environment(NavigationManager())
        .environment(HealthManager())
        .environment(BluetoothManager())
}
