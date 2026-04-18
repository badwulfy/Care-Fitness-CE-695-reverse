import SwiftUI

struct WelcomePage: View {
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

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        WelcomePage()
    }
}
