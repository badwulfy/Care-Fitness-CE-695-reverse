//
//  HistoryView.swift
//  opencarefitness
//
//  Workout history list powered by SwiftData.
//  Tap to see details, swipe to delete, export as JSON.
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("Historique")
            .background(Color.appBackground)
            .toolbar {
                if !sessions.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            exportJSON()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.elliptical")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Aucune séance")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Tes séances apparaîtront ici\naprès ton premier entraînement.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink(value: session) {
                    SessionRow(session: session)
                }
                .listRowBackground(Color.white.opacity(0.03))
                .listRowSeparatorTint(.white.opacity(0.06))
            }
            .onDelete(perform: deleteSessions)
        }
        .listStyle(.plain)
        .navigationDestination(for: WorkoutSession.self) { session in
            SessionDetailView(session: session)
        }
    }

    // MARK: - Actions

    private func deleteSessions(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(sessions[index])
            }
        }
    }

    private func exportJSON() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        struct ExportSession: Codable {
            let date: Date
            let pattern: String
            let duration: Int
            let distance: Int
            let calories: Int
            let avgHR: Int
            let maxHR: Int
            let avgWatts: Int
            let maxWatts: Int
            let avgRPM: Int
            let maxIncline: Double
        }

        let exportData = sessions.map { s in
            ExportSession(
                date: s.date,
                pattern: s.patternName,
                duration: s.durationSeconds,
                distance: s.distanceTotal,
                calories: s.caloriesTotal,
                avgHR: s.avgHeartRate,
                maxHR: s.maxHeartRate,
                avgWatts: s.avgWatts,
                maxWatts: s.maxWatts,
                avgRPM: s.avgRPM,
                maxIncline: s.maxIncline
            )
        }

        guard let jsonData = try? encoder.encode(exportData),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        #if os(iOS)
        let activityVC = UIActivityViewController(
            activityItems: [jsonString],
            applicationActivities: nil
        )
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(jsonString, forType: .string)
        #endif
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 16) {
            // Pattern icon
            VStack {
                Image(systemName: patternIcon)
                    .font(.title3)
                    .foregroundStyle(Color.neonCyan)
            }
            .frame(width: 40, height: 40)
            .glassPanel(cornerRadius: 12)

            // Date & Pattern
            VStack(alignment: .leading, spacing: 4) {
                Text(session.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    Text(session.patternName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.neonCyan.opacity(0.15))
                        .foregroundStyle(Color.neonCyan)
                        .clipShape(Capsule())

                    Text(formatDuration(session.durationSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Key stats
            HStack(spacing: 16) {
                miniStat(
                    value: String(format: "%.1f", Double(session.distanceTotal) / 10.0),
                    unit: "km",
                    color: .white
                )
                miniStat(
                    value: "\(session.caloriesTotal)",
                    unit: "kcal",
                    color: .neonOrange
                )
                miniStat(
                    value: "\(session.avgWatts)",
                    unit: "W",
                    color: .neonYellow
                )
            }
        }
        .padding(.vertical, 6)
    }

    private var patternIcon: String {
        if let pattern = WorkoutPattern(rawValue: session.patternName) {
            return pattern.icon
        }
        return "figure.elliptical"
    }

    private func miniStat(value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.callout, design: .monospaced, weight: .bold))
                .foregroundStyle(color)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 40)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Previews

#Preview("History — iPhone") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: WorkoutSession.self, configurations: config)

    // Insert sample data
    let samples: [(String, Int, Int, Int, Int, Int)] = [
        ("Pyramide",  2700, 128, 412, 142, 185),
        ("HIIT",      1800,  85, 280, 158, 220),
        ("Plat",      3600, 180, 520, 125, 150),
        ("Collines",  2400, 110, 350, 138, 175),
    ]
    for (i, s) in samples.enumerated() {
        let session = WorkoutSession(
            date: Calendar.current.date(byAdding: .day, value: -i, to: .now)!,
            patternName: s.0,
            durationSeconds: s.1,
            distanceTotal: s.2,
            caloriesTotal: s.3,
            avgHeartRate: s.4,
            maxHeartRate: s.4 + 20,
            avgWatts: s.5,
            maxWatts: s.5 + 80,
            avgRPM: 65,
            maxIncline: 12.0
        )
        container.mainContext.insert(session)
    }

    return HistoryView()
        .modelContainer(container)
        .preferredColorScheme(.dark)
}

#Preview("History — iPad Landscape", traits: .landscapeLeft) {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: WorkoutSession.self, configurations: config)

    // Insert sample data
    let samples: [(String, Int, Int, Int, Int, Int)] = [
        ("Pyramide",  2700, 128, 412, 142, 185),
        ("HIIT",      1800,  85, 280, 158, 220),
        ("Plat",      3600, 180, 520, 125, 150),
        ("Collines",  2400, 110, 350, 138, 175),
    ]
    for (i, s) in samples.enumerated() {
        let session = WorkoutSession(
            date: Calendar.current.date(byAdding: .day, value: -i, to: .now)!,
            patternName: s.0,
            durationSeconds: s.1,
            distanceTotal: s.2,
            caloriesTotal: s.3,
            avgHeartRate: s.4,
            maxHeartRate: s.4 + 20,
            avgWatts: s.5,
            maxWatts: s.5 + 80,
            avgRPM: 65,
            maxIncline: 12.0
        )
        container.mainContext.insert(session)
    }

    return HistoryView()
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
