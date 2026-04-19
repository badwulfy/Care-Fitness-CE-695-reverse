import SwiftUI
import WatchKit
import HealthKit

@main
struct opencarefitnesswatch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @State private var workoutManager = WorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(workoutManager)
        }
    }
}

@Observable
final class WorkoutManager: NSObject {
    static let shared = WorkoutManager()

    var heartRate: Int = 0
    var isAuthorized: Bool = false
    var isWorkoutActive: Bool = false
    var statusMessage: String?
    var debugLogs: [String] = []

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private override init() {
        super.init()
        statusMessage = "Autorise Santé sur la montre pour activer le mirroring."
        log("WorkoutManager initialise.")
        refreshAuthorizationStatus()
    }

    func log(_ message: String) {
        let line = "[Watch] \(message)"
        print(line)
        Task { @MainActor in
            self.debugLogs.append(line)
            if self.debugLogs.count > 20 {
                self.debugLogs.removeFirst(self.debugLogs.count - 20)
            }
        }
    }

    func requestAuthorization() async {
        log("Bouton Autoriser Santé cliqué.")
        guard HKHealthStore.isHealthDataAvailable() else {
            log("HealthKit indisponible sur cette montre.")
            await MainActor.run {
                statusMessage = "HealthKit indisponible sur cette montre."
            }
            return
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.workoutType()
        ]

        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!
        ]

        do {
            log("Demande d'autorisation HealthKit envoyée.")
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            log("requestAuthorization termine sans exception.")
            let workoutStatus = store.authorizationStatus(for: HKObjectType.workoutType())
            let heartRateStatus = store.authorizationStatus(for: HKObjectType.quantityType(forIdentifier: .heartRate)!)
            log("Statut workout=\(workoutStatus.rawValue), heartRate=\(heartRateStatus.rawValue)")
            refreshAuthorizationStatus()
            await MainActor.run {
                statusMessage = "Santé autorisé sur la montre. Lance le test depuis l’iPhone."
            }
        } catch {
            log("requestAuthorization a echoue: \(error.localizedDescription)")
            refreshAuthorizationStatus()
            await MainActor.run {
                statusMessage = "Autorisation refusée: \(error.localizedDescription)"
            }
        }
    }

    func startWorkout(with configuration: HKWorkoutConfiguration) async {
        log("Demande de demarrage workout recue depuis l'iPhone.")
        do {
            try await requestAuthorizationIfNeeded()
            try await startPrimaryWorkout(with: configuration)
        } catch {
            log("Demarrage workout impossible: \(error.localizedDescription)")
            await MainActor.run {
                statusMessage = "Impossible de démarrer le workout: \(error.localizedDescription)"
                isWorkoutActive = false
            }
        }
    }

    func refreshAuthorizationStatus() {
        let workoutStatus = store.authorizationStatus(for: HKObjectType.workoutType())
        let authorized = (workoutStatus == .sharingAuthorized)
        Task { @MainActor in
            self.isAuthorized = authorized
            if !self.isWorkoutActive {
                self.statusMessage = authorized
                    ? "Santé autorisé sur la montre. Lance le test depuis l’iPhone."
                    : "Autorise Santé sur la montre pour activer le mirroring."
            }
        }
        log("refreshAuthorizationStatus -> workout=\(workoutStatus.rawValue), authorized=\(authorized)")
    }

    func endWorkout() async {
        log("Demande d'arret workout.")
        guard let session, let builder else { return }

        let endDate = Date()
        session.stopActivity(with: endDate)

        do {
            try await builder.endCollection(at: endDate)
            try await builder.finishWorkout()
            try await session.stopMirroringToCompanionDevice()
            log("Workout termine et mirroring arrete.")
        } catch {
            log("Erreur pendant la fin du workout: \(error.localizedDescription)")
            await MainActor.run {
                statusMessage = "Erreur de fin de workout: \(error.localizedDescription)"
            }
        }

        session.end()
        await MainActor.run {
            self.session = nil
            self.builder = nil
            self.isWorkoutActive = false
            self.heartRate = 0
        }
    }

    private func requestAuthorizationIfNeeded() async throws {
        let workoutStatus = store.authorizationStatus(for: HKObjectType.workoutType())
        log("Verification authorization workout status=\(workoutStatus.rawValue)")
        if workoutStatus == .notDetermined {
            log("Authorization non determinee, demande en cours.")
            await requestAuthorization()
        }
        if store.authorizationStatus(for: HKObjectType.workoutType()) != .sharingAuthorized {
            log("Authorization workout refusee apres verification.")
            throw HKError(.errorAuthorizationDenied)
        }
        refreshAuthorizationStatus()
        log("Authorization workout validee.")
    }

    private func startPrimaryWorkout(with configuration: HKWorkoutConfiguration) async throws {
        if isWorkoutActive {
            log("Workout deja actif, aucune action.")
            return
        }

        log("Creation de la session workout primaire.")
        let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        dataSource.enableCollection(for: HKQuantityType(.heartRate), predicate: nil)
        dataSource.enableCollection(for: HKQuantityType(.activeEnergyBurned), predicate: nil)

        builder.dataSource = dataSource
        session.delegate = self
        builder.delegate = self

        self.session = session
        self.builder = builder

        log("Demarrage du mirroring vers l'iPhone.")
        try await session.startMirroringToCompanionDevice()

        let startDate = Date()
        log("Demarrage session.startActivity et builder.beginCollection.")
        session.startActivity(with: startDate)
        try await builder.beginCollection(at: startDate)

        log("Workout primaire demarre sur la montre.")
        await MainActor.run {
            self.isWorkoutActive = true
            self.statusMessage = "Mirroring actif vers l’iPhone."
        }
    }

    private func sendHeartRateToPhone(_ heartRate: Int) {
        guard let session else { return }
        do {
            let payload = try JSONEncoder().encode(HeartRatePayload(heartRate: heartRate))
            Task {
                do {
                    try await session.sendToRemoteWorkoutSession(data: payload)
                    self.log("Frequence \(heartRate) BPM envoyee a l'iPhone.")
                } catch {
                    self.log("Envoi iPhone echoue: \(error.localizedDescription)")
                }
            }
        } catch {
            log("Encodage payload HR impossible: \(error.localizedDescription)")
            Task { @MainActor in
                self.statusMessage = "Envoi iPhone impossible: \(error.localizedDescription)"
            }
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        log("Session state \(fromState.rawValue) -> \(toState.rawValue)")
        Task { @MainActor in
            self.isWorkoutActive = (toState == .running)
            if toState == .ended || toState == .stopped {
                self.heartRate = 0
                self.statusMessage = "Workout arrêté sur la montre."
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        log("Session en erreur: \(error.localizedDescription)")
        Task { @MainActor in
            self.statusMessage = "Session watch en erreur: \(error.localizedDescription)"
            self.isWorkoutActive = false
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        log("Builder didCollectDataOf avec \(collectedTypes.count) types.")
        guard collectedTypes.contains(HKQuantityType(.heartRate)),
              let statistics = workoutBuilder.statistics(for: HKQuantityType(.heartRate)),
              let quantity = statistics.mostRecentQuantity() else {
            log("Pas de heart rate exploitable dans ce batch.")
            return
        }

        let heartRate = Int(quantity.doubleValue(for: .count().unitDivided(by: .minute())))
        log("Heart rate recue sur la montre: \(heartRate) BPM")
        Task { @MainActor in
            self.heartRate = heartRate
            self.statusMessage = "Fréquence cardiaque mesurée sur la montre."
        }
        sendHeartRateToPhone(heartRate)
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        print("[Watch] handle(workoutConfiguration:) appele par le systeme.")
        Task {
            await WorkoutManager.shared.startWorkout(with: workoutConfiguration)
        }
    }

    func handleActiveWorkoutRecovery() {
        print("[Watch] handleActiveWorkoutRecovery appele.")
        Task {
            do {
                if let recoveredSession = try await HKHealthStore().recoverActiveWorkoutSession() {
                    let manager = WorkoutManager.shared
                    let builder = recoveredSession.associatedWorkoutBuilder()
                    recoveredSession.delegate = manager
                    builder.delegate = manager
                    manager.log("Session workout recuperee apres relance.")
                    await MainActor.run {
                        manager.statusMessage = "Workout récupéré après relance."
                    }
                }
            } catch {
                WorkoutManager.shared.log("Recovery impossible: \(error.localizedDescription)")
                await MainActor.run {
                    WorkoutManager.shared.statusMessage = "Recovery impossible: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct HeartRatePayload: Codable {
    let heartRate: Int
}
