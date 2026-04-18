import SwiftUI

struct FinalPage: View {
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

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        FinalPage()
    }
}
