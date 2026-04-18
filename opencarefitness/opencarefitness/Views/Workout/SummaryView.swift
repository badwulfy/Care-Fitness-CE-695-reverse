//
//  SummaryView.swift
//  opencarefitness
//
//  Post-workout summary screen with key stats,
//  HealthKit save option, and return to setup.
//

import SwiftUI

struct SummaryView: View {
    let session: WorkoutSession
    @Environment(HealthManager.self) private var health
    var onDismiss: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {

                // MARK: - Title
                VStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.neonCyan)
                        .shadow(color: Color.neonCyan.opacity(0.5), radius: 15)

                    Text("Excellent Travail !")
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("\(session.patternName) • \(formatDuration(session.durationSeconds))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Stats Grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    SummaryStat(
                        label: "Distance",
                        value: String(format: "%.1f km", Double(session.distanceTotal) / 10.0),
                        color: .white
                    )
                    SummaryStat(
                        label: "Énergie",
                        value: "\(session.caloriesTotal) kcal",
                        color: .neonOrange
                    )
                    SummaryStat(
                        label: "Puis. Moy.",
                        value: "\(session.avgWatts) W",
                        color: .neonYellow
                    )
                    SummaryStat(
                        label: "FC Moy.",
                        value: session.avgHeartRate > 0 ? "\(session.avgHeartRate) bpm" : "-- bpm",
                        color: .neonRed
                    )
                    SummaryStat(
                        label: "Cadence",
                        value: "\(session.avgRPM) RPM",
                        color: .neonCyan
                    )
                    SummaryStat(
                        label: "Pente Max",
                        value: String(format: "%.1f %%", session.maxIncline),
                        color: .neonPurple
                    )
                }

                // MARK: - Actions
                VStack(spacing: 20) {
                    // Sync Badge
                    HStack(spacing: 8) {
                        ZStack {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .offset(x: 4, y: 4)
                                .foregroundStyle(.white)
                        }
                        Text("DONNÉES SÉCURISÉES DANS SANTÉ")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())

                    // Return button
                    Button(action: onDismiss) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.left")
                            Text("RETOUR AU SETUP")
                                .fontWeight(.bold)
                                .tracking(1)
                        }
                        .font(.callout)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                        .glassPanel(cornerRadius: 30)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            .padding(24)
            .glassPanel(cornerRadius: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 32)
                    .stroke(Color.neonCyan.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 40)
        }
        .background(Color.appBackground)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Summary Stat Cell

private struct SummaryStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .neonGlow(color, radius: 8)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Previews

#Preview("Summary — iPhone") {
    SummaryView(
        session: WorkoutSession(
            date: .now,
            patternName: "Vallon",
            durationSeconds: 2700,
            distanceTotal: 128,
            caloriesTotal: 412,
            avgHeartRate: 142,
            maxHeartRate: 178,
            avgWatts: 185,
            maxWatts: 310,
            avgRPM: 65,
            maxIncline: 12.5
        ),
        onDismiss: { }
    )
    .environment(HealthManager())
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}

#Preview("Summary — iPad Landscape", traits: .landscapeLeft) {
    SummaryView(
        session: WorkoutSession(
            date: .now,
            patternName: "Vallon",
            durationSeconds: 2700,
            distanceTotal: 128,
            caloriesTotal: 412,
            avgHeartRate: 142,
            maxHeartRate: 178,
            avgWatts: 185,
            maxWatts: 310,
            avgRPM: 65,
            maxIncline: 12.5
        ),
        onDismiss: { }
    )
    .environment(HealthManager())
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
