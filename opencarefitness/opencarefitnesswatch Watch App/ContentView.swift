import SwiftUI

struct ContentView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @State private var isRequestInFlight = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(workoutManager.isWorkoutActive ? "Séance active" : "Prêt")
                    .font(.headline)

                Text(workoutManager.isAuthorized ? "Santé autorisé" : "Santé non autorisé")
                    .font(.caption)
                    .foregroundStyle(workoutManager.isAuthorized ? .green : .orange)

                if isRequestInFlight {
                    ProgressView().controlSize(.small)
                }

                Text(workoutManager.heartRate > 0 ? "\(workoutManager.heartRate) BPM" : "— BPM")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(workoutManager.heartRate > 0 ? .red : .secondary)

                if let message = workoutManager.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !workoutManager.isAuthorized {
                    Button("Autoriser Santé") {
                        Task {
                            isRequestInFlight = true
                            await workoutManager.requestAuthorization()
                            isRequestInFlight = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else if workoutManager.isWorkoutActive {
                    Button("Arrêter", role: .destructive) {
                        Task {
                            isRequestInFlight = true
                            await workoutManager.endWorkout()
                            isRequestInFlight = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

#Preview {
    ContentView()
        .environment(WorkoutManager.shared)
}
