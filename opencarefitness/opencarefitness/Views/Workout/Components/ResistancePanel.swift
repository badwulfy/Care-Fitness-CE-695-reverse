//
//  ResistancePanel.swift
//  opencarefitness
//

import SwiftUI

struct ResistancePanel: View {
    @Environment(PatternEngine.self) private var engine
    let isPad: Bool
    var safeAreaTrailing: CGFloat = 0
    
    var body: some View {
        VStack(spacing: isPad ? 20 : 12) {
            // + Button
            Button {
                withAnimation(.easeOut(duration: 0.1)) {
                    engine.incrementIncline()
                }
            } label: {
                Text("+")
                    .font(.system(size: isPad ? 56 : 40, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassPanel(cornerRadius: 32)
            }
            .buttonStyle(HitButtonStyle())

            // Override status
            VStack(spacing: 2) {
                Text("OFFSET")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(isDefaultMultiplier ? "OFF" : String(format: "x%.2f", engine.difficultyMultiplier))
                    .font(.system(size: isPad ? 14 : 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isDefaultMultiplier ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.neonCyan))
            }
            .padding(.vertical, 4)

            // - Button
            Button {
                withAnimation(.easeOut(duration: 0.1)) {
                    engine.decrementIncline()
                }
            } label: {
                Text("−")
                    .font(.system(size: isPad ? 56 : 40, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassPanel(cornerRadius: 32)
            }
            .buttonStyle(HitButtonStyle())
        }
        .padding(.vertical, 20)
        .padding(.horizontal, isPad ? 12 : 8)
        .padding(.trailing, isPad ? 0 : max(0, safeAreaTrailing - 8)) // Repousse les boutons pour éviter l'encoche
        .frame(maxHeight: .infinity, alignment: .center)
        .background(
            Color.black.opacity(0.4)
                .ignoresSafeArea(.all, edges: .all)
        )
        .overlay(
            Group {
                if isPad {
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        )
    }
    
    private var isDefaultMultiplier: Bool {
        abs(engine.difficultyMultiplier - engine.difficulty.multiplier) < 0.01
    }
}

// MARK: - Hit Button Style (for sweaty-finger tapping)

private struct HitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
