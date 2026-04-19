import SwiftUI

struct ContentView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @State private var isRequestInFlight = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(workoutManager.isWorkoutActive ? "Workout actif" : "Prêt")
                    .font(.headline)

                Text(workoutManager.isAuthorized ? "Santé autorisé" : "Santé non autorisé")
                    .font(.caption)
                    .foregroundStyle(workoutManager.isAuthorized ? .green : .orange)

                if isRequestInFlight {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("\(workoutManager.heartRate) BPM")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)

                if let message = workoutManager.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(primaryButtonTitle) {
                    Task {
                        isRequestInFlight = true
                        if workoutManager.isWorkoutActive {
                            await workoutManager.endWorkout()
                        } else if !workoutManager.isAuthorized {
                            await workoutManager.requestAuthorization()
                        } else {
                            workoutManager.refreshAuthorizationStatus()
                        }
                        isRequestInFlight = false
                    }
                }
                .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Logs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(Array(workoutManager.debugLogs.enumerated()), id: \.offset) { _, log in
                        Text(log)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private var primaryButtonTitle: String {
        if workoutManager.isWorkoutActive {
            return "Arrêter"
        }
        if workoutManager.isAuthorized {
            return "En attente de l’iPhone"
        }
        return "Autoriser Santé"
    }
}

#Preview {
    ContentView()
        .environment(WorkoutManager.shared)
}
