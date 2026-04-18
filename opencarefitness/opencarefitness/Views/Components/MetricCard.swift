//
//  MetricCard.swift
//  opencarefitness
//
//  Reusable metric display card for the workout dashboard.
//

import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    var icon: String? = nil
    var isLarge: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Spacer()

                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.system(size: 10))
                }
            }

            // Value row
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(
                        size: isLarge ? 44 : 28,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .neonGlow(color, radius: 6)
                    .contentTransition(.numericText())

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
    }
}

// MARK: - Dual Metric (Distance + Calories)

struct DualMetricCard: View {
    let leftTitle: String
    let leftValue: String
    let leftUnit: String
    let rightTitle: String
    let rightValue: String
    let rightUnit: String
    let rightColor: Color

    var body: some View {
        HStack(spacing: 0) {
            // Left
            VStack(alignment: .leading, spacing: 8) {
                Text(leftTitle)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(leftValue)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Text(leftUnit)
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Divider
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 8)

            // Right
            VStack(alignment: .trailing, spacing: 8) {
                Text(rightTitle)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(rightValue)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .neonGlow(rightColor)
                    Text(rightUnit)
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel()
    }
}

// MARK: - Previews

#Preview("Metric Cards") {
    HStack(spacing: 12) {
        MetricCard(
            title: "Pulse ⌚",
            value: "142",
            unit: "bpm",
            color: .neonRed,
            icon: "heart.fill"
        )
        MetricCard(
            title: "Puissance",
            value: "185",
            unit: "W",
            color: .neonYellow
        )
        DualMetricCard(
            leftTitle: "Distance",
            leftValue: "4.2",
            leftUnit: "km",
            rightTitle: "Calories",
            rightValue: "115",
            rightUnit: "kcal",
            rightColor: .neonOrange
        )
    }
    .frame(height: 160)
    .padding()
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
