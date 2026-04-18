import SwiftUI

struct HealthPermissionPage: View {
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
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        HealthPermissionPage(isAuthorized: .constant(false), requestAction: {})
    }
}
