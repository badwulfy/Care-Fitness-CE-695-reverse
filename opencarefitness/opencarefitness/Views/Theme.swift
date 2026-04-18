//
//  Theme.swift
//  opencarefitness
//
//  Design system: colors, Liquid Glass panels, and neon glow modifiers.
//  Uses iOS 26 / macOS 26 Liquid Glass where available.
//

import SwiftUI

// MARK: - Color Palette

extension Color {
    static let appBackground  = Color(red: 0.02, green: 0.03, blue: 0.06)
    static let cardBackground = Color(white: 1, opacity: 0.04)
    static let cardBorder     = Color(white: 1, opacity: 0.06)

    // Neon accent colors
    static let neonRed    = Color(red: 1.0, green: 0.2, blue: 0.4)
    static let neonYellow = Color(red: 0.98, green: 0.8, blue: 0.08)
    static let neonCyan   = Color(red: 0.02, green: 0.71, blue: 0.83)
    static let neonGreen  = Color(red: 0.29, green: 0.87, blue: 0.50)
    static let neonOrange = Color(red: 0.98, green: 0.57, blue: 0.24)
    static let neonPurple = Color(red: 0.6, green: 0.3, blue: 1.0)
    static let neonBlue   = Color(red: 0.2, green: 0.5, blue: 1.0)
}

// MARK: - Glass Panel Modifier (Liquid Glass)

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}

// MARK: - Neon Text Modifier

struct NeonGlow: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.5), radius: radius)
    }
}

extension View {
    func neonGlow(_ color: Color, radius: CGFloat = 10) -> some View {
        modifier(NeonGlow(color: color, radius: radius))
    }
}
