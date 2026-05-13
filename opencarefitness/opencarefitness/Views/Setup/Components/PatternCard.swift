//
//  PatternCard.swift
//  opencarefitness
//

import SwiftUI

struct PatternCard: View {
    @Environment(PatternEngine.self) private var engine
    let pattern: WorkoutPattern
    let isSelected: Bool
    let difficulty: WorkoutDifficulty

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: pattern.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.neonCyan : .white.opacity(0.6))
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.neonCyan)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(pattern.rawValue)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            PatternPreviewChart(
                pattern: pattern,
                isSelected: isSelected,
                difficulty: difficulty
            )
            .frame(height: 48)
            // Swift Charts mis-animates BarMark foregroundStyle transitions
            // (cyan ↔ white) under our parent .spring animation — opt out.
            .transaction { $0.animation = nil }

            Text(pattern.description)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isSelected
                        ? Color.neonCyan.opacity(0.12)
                        : Color.white.opacity(0.04)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isSelected
                                    ? Color.neonCyan.opacity(0.55)
                                    : Color.white.opacity(0.07),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .shadow(
            color: isSelected ? Color.neonCyan.opacity(0.15) : .clear,
            radius: 12
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
