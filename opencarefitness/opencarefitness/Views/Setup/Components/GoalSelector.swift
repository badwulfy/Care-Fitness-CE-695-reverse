//
//  GoalSelector.swift
//  opencarefitness
//

import SwiftUI

struct GoalSelector: View {
    let title: String
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let quickSelects: [Double]
    let format: (Double) -> String
    let onUpdate: (Double) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Large value display
            HStack(alignment: .center, spacing: 20) {
                StepperButton(icon: "minus") {
                    if value > range.lowerBound {
                        withAnimation(.spring(response: 0.2)) {
                            value -= step
                            onUpdate(value)
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(format(value))
                        .font(.system(size: 52, weight: .heavy, design: .monospaced))
                        .neonGlow(.neonCyan)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(minWidth: 100)

                StepperButton(icon: "plus") {
                    if value < range.upperBound {
                        withAnimation(.spring(response: 0.2)) {
                            value += step
                            onUpdate(value)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Quick-select chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(quickSelects, id: \.self) { chipValue in
                        GoalChip(
                            title: format(chipValue) + " " + unit,
                            isSelected: abs(value - chipValue) < 0.001
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                value = chipValue
                                onUpdate(value)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, -16)
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 24)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 24)
                }
            }
        }
    }
}

// MARK: - Sub-components

private struct StepperButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background {
                    Circle().fill(.white.opacity(0.08))
                        .overlay { Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1) }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct GoalChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    Capsule().fill(isSelected ? Color.neonCyan.opacity(0.2) : Color.white.opacity(0.06))
                        .overlay { Capsule().strokeBorder(isSelected ? Color.neonCyan.opacity(0.5) : Color.clear, lineWidth: 1) }
                }
                .foregroundStyle(isSelected ? Color.neonCyan : .white.opacity(0.45))
        }
        .buttonStyle(.plain)
    }
}
