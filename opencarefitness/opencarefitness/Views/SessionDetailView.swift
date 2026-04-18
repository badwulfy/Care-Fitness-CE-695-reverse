//
//  SessionDetailView.swift
//  opencarefitness
//
//  Detailed view for a single workout session from history.
//  Shows all recorded metrics in a premium layout.
//

import SwiftUI

struct SessionDetailView: View {
    let session: WorkoutSession

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // MARK: - Header
                VStack(spacing: 8) {
                    Image(systemName: "figure.elliptical")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.neonCyan)
                        .shadow(color: Color.neonCyan.opacity(0.4), radius: 12)

                    Text(session.patternName)
                        .font(.title2.weight(.heavy))

                    Text(session.date, format: .dateTime.day().month(.wide).year().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(formatDuration(session.durationSeconds))
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .white.opacity(0.3), radius: 10)
                }
                .padding(.top, 16)

                // MARK: - Stats Grid
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    DetailStat(
                        icon: "road.lanes",
                        label: "Distance",
                        value: String(format: "%.1f", Double(session.distanceTotal) / 10.0),
                        unit: "km",
                        color: .white
                    )
                    DetailStat(
                        icon: "flame.fill",
                        label: "Calories",
                        value: "\(session.caloriesTotal)",
                        unit: "kcal",
                        color: .neonOrange
                    )
                    DetailStat(
                        icon: "bolt.fill",
                        label: "Puissance Moy.",
                        value: "\(session.avgWatts)",
                        unit: "W",
                        color: .neonYellow
                    )
                    DetailStat(
                        icon: "bolt.trianglebadge.exclamationmark.fill",
                        label: "Puissance Max",
                        value: "\(session.maxWatts)",
                        unit: "W",
                        color: .neonYellow
                    )
                    DetailStat(
                        icon: "heart.fill",
                        label: "FC Moyenne",
                        value: session.avgHeartRate > 0 ? "\(session.avgHeartRate)" : "--",
                        unit: "bpm",
                        color: .neonRed
                    )
                    DetailStat(
                        icon: "heart.circle.fill",
                        label: "FC Max",
                        value: session.maxHeartRate > 0 ? "\(session.maxHeartRate)" : "--",
                        unit: "bpm",
                        color: .neonRed
                    )
                    DetailStat(
                        icon: "gauge.with.dots.needle.33percent",
                        label: "Cadence Moy.",
                        value: "\(session.avgRPM)",
                        unit: "RPM",
                        color: .neonCyan
                    )
                    DetailStat(
                        icon: "arrow.up.right",
                        label: "Pente Max",
                        value: String(format: "%.1f", session.maxIncline),
                        unit: "%",
                        color: .neonPurple
                    )
                }
                .padding(.horizontal, 8)
            }
            .padding(24)
        }
        .background(Color.appBackground)
        .navigationTitle("Détails")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Detail Stat Card

private struct DetailStat: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .neonGlow(color, radius: 6)
                Text(unit)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .glassPanel(cornerRadius: 16)
    }
}

// MARK: - Previews

#Preview("Detail — iPhone") {
    NavigationStack {
        SessionDetailView(
            session: WorkoutSession(
                date: .now,
                patternName: "Pyramide",
                durationSeconds: 2700,
                distanceTotal: 128,
                caloriesTotal: 412,
                avgHeartRate: 142,
                maxHeartRate: 178,
                avgWatts: 185,
                maxWatts: 310,
                avgRPM: 65,
                maxIncline: 12.5
            )
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Detail — iPad Landscape", traits: .landscapeLeft) {
    NavigationStack {
        SessionDetailView(
            session: WorkoutSession(
                date: .now,
                patternName: "Pyramide",
                durationSeconds: 2700,
                distanceTotal: 128,
                caloriesTotal: 412,
                avgHeartRate: 142,
                maxHeartRate: 178,
                avgWatts: 185,
                maxWatts: 310,
                avgRPM: 65,
                maxIncline: 12.5
            )
        )
    }
    .preferredColorScheme(.dark)
}
