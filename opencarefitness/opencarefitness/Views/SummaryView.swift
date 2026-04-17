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
    var healthManager: HealthManager
    var onDismiss: () -> Void

    @State private var isSaved = false
    @State private var showSaveAnimation = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {

                // MARK: - Title
                VStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.neonCyan)
                        .shadow(color: Color.neonCyan.opacity(0.5), radius: 20)

                    Text("Excellent Travail !")
                        .font(.system(size: 36, weight: .heavy))
                        .tracking(1)

                    Text("\(session.patternName) • \(formatDuration(session.durationSeconds))")
                        .foregroundStyle(.secondary)
                }

                // MARK: - Stats Grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 16
                ) {
                    SummaryStat(
                        label: "Distance Totale",
                        value: String(format: "%.1f km", Double(session.distanceTotal) / 10.0),
                        color: .white
                    )
                    SummaryStat(
                        label: "Énergie",
                        value: "\(session.caloriesTotal) kcal",
                        color: .neonOrange
                    )
                    SummaryStat(
                        label: "Puissance Moy.",
                        value: "\(session.avgWatts) W",
                        color: .neonYellow
                    )
                    SummaryStat(
                        label: "FC Moyenne",
                        value: session.avgHeartRate > 0 ? "\(session.avgHeartRate) bpm" : "-- bpm",
                        color: .neonRed
                    )
                    SummaryStat(
                        label: "Cadence Moy.",
                        value: "\(session.avgRPM) RPM",
                        color: .neonCyan
                    )
                    SummaryStat(
                        label: "Pente Max",
                        value: String(format: "%.1f %%", session.maxIncline),
                        color: .neonPurple
                    )
                }
                .padding(.horizontal, 8)

                // MARK: - Actions
                HStack(spacing: 16) {
                    // Return button
                    Button(action: onDismiss) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left")
                            Text("RETOUR")
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .glassPanel(cornerRadius: 28)
                    }
                    .buttonStyle(.plain)

                    // Save to Health button (iOS only)
                    #if os(iOS)
                    Button {
                        Task {
                            await healthManager.saveWorkoutSummary(
                                duration: Double(session.durationSeconds),
                                calories: Double(session.caloriesTotal),
                                distance: Double(session.distanceTotal) * 100 // hm → meters (approx)
                            )
                            withAnimation(.spring()) {
                                isSaved = true
                                showSaveAnimation = true
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isSaved ? "checkmark" : "heart.fill")
                            Text(isSaved ? "Enregistré !" : "Sauver dans Santé")
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(isSaved ? Color.neonGreen : Color.neonRed)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(
                            color: (isSaved ? Color.neonGreen : Color.neonRed).opacity(0.4),
                            radius: 15
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaved)
                    #endif
                }
            }
            .padding(40)
            .glassPanel(cornerRadius: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 32)
                    .stroke(Color.neonCyan.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 48)

            Spacer()
        }
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
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .neonGlow(color, radius: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Preview

#Preview("Summary") {
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
        healthManager: HealthManager(),
        onDismiss: { }
    )
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
