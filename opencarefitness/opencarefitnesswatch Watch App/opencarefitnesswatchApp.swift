import SwiftUI
import WatchKit
import HealthKit
import WatchConnectivity

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

// MARK: - WorkoutManager

@Observable
final class WorkoutManager: NSObject {
    static let shared = WorkoutManager()

    var heartRate: Int = 0
    var isAuthorized: Bool = false
    var isWorkoutActive: Bool = false
    var statusMessage: String?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var wcSession: WCSession?
    /// Test session (iPhone Settings) → discard workout on stop instead of saving.
    private var isTestSession: Bool = false

    private override init() {
        super.init()
        statusMessage = "Autorise Santé sur la montre, puis lance la séance depuis l’iPhone."
        refreshAuthorizationStatus()
        activateWatchConnectivity()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            await MainActor.run { statusMessage = "HealthKit indisponible sur cette montre." }
            return
        }
        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.workoutType()
        ]
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        } catch {
            await MainActor.run { statusMessage = "Autorisation refusée: \(error.localizedDescription)" }
        }
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        let workoutStatus = store.authorizationStatus(for: HKObjectType.workoutType())
        let authorized = (workoutStatus == .sharingAuthorized)
        Task { @MainActor in
            self.isAuthorized = authorized
            if !self.isWorkoutActive {
                self.statusMessage = authorized
                    ? "Prêt. Lance la séance depuis l’iPhone."
                    : "Autorise Santé sur la montre pour activer le suivi cardiaque."
            }
        }
    }

    // MARK: - Workout (iPhone-controlled)

    func startWorkout(isTest: Bool = false) async {
        guard !isWorkoutActive else { return }
        if !isAuthorized { await requestAuthorization() }
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            sendToPhone(["state": "error", "message": "Santé non autorisé sur la montre."])
            return
        }
        await MainActor.run { self.isTestSession = isTest }

        let config = HKWorkoutConfiguration()
        config.activityType = .elliptical
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            dataSource.enableCollection(for: HKQuantityType(.heartRate), predicate: nil)
            dataSource.enableCollection(for: HKQuantityType(.activeEnergyBurned), predicate: nil)
            builder.dataSource = dataSource
            session.delegate = self
            builder.delegate = self

            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)

            await MainActor.run {
                self.session = session
                self.builder = builder
                self.isWorkoutActive = true
                self.statusMessage = "Mesure cardiaque en cours."
            }
            sendToPhone(["state": "started"])
        } catch {
            sendToPhone(["state": "error", "message": error.localizedDescription])
            await MainActor.run {
                self.statusMessage = "Impossible de démarrer: \(error.localizedDescription)"
                self.isWorkoutActive = false
            }
        }
    }

    func endWorkout() async {
        guard let session, let builder else {
            await MainActor.run {
                self.isWorkoutActive = false
                self.heartRate = 0
            }
            sendToPhone(["state": "ended"])
            return
        }

        let endDate = Date()
        // Synchronous, fast — stops the sensors right away.
        session.stopActivity(with: endDate)

        // Flip UI immediately; Health writes happen below in the background.
        let testMode = isTestSession
        await MainActor.run {
            self.isWorkoutActive = false
            self.heartRate = 0
            self.statusMessage = testMode ? "Test terminé." : "Sauvegarde en cours…"
            self.isTestSession = false
        }
        sendToPhone(["state": "ended"])

        do {
            try await builder.endCollection(at: endDate)
            if testMode {
                // Don't persist the workout — Settings test isn't a real session.
                builder.discardWorkout()
            } else {
                try await builder.finishWorkout()
            }
        } catch {
            print("[Watch] endWorkout error: \(error.localizedDescription)")
        }
        session.end()

        await MainActor.run {
            self.session = nil
            self.builder = nil
            if !testMode { self.statusMessage = "Séance terminée." }
        }
    }

    // MARK: - WatchConnectivity

    private func activateWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        wcSession = s
    }

    private func sendToPhone(_ payload: [String: Any]) {
        guard let s = wcSession, s.activationState == .activated else { return }

        // HR streaming: applicationContext keeps flowing in background (when
        // Watch screen is off but HKWorkoutSession keeps us alive). It has
        // latest-value-wins semantics, which is exactly what we want.
        if payload.keys.contains("hr") {
            do { try s.updateApplicationContext(payload) }
            catch { print("[WC] updateApplicationContext failed: \(error.localizedDescription)") }
            return
        }

        // Commands/state: try live message first, fall back to queued userInfo.
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil) { err in
                print("[WC] sendMessage failed: \(err.localizedDescription)")
                s.transferUserInfo(payload)
            }
        } else {
            s.transferUserInfo(payload)
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        Task { @MainActor in
            self.isWorkoutActive = (toState == .running)
            if toState == .ended || toState == .stopped {
                self.heartRate = 0
                self.statusMessage = "Séance arrêtée."
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        sendToPhone(["state": "error", "message": error.localizedDescription])
        Task { @MainActor in
            self.statusMessage = "Erreur session: \(error.localizedDescription)"
            self.isWorkoutActive = false
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)),
              let stats = workoutBuilder.statistics(for: HKQuantityType(.heartRate)),
              let q = stats.mostRecentQuantity() else { return }

        let hr = Int(q.doubleValue(for: .count().unitDivided(by: .minute())))
        Task { @MainActor in self.heartRate = hr }
        sendToPhone(["hr": hr])
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
}

// MARK: - WCSessionDelegate

extension WorkoutManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("[WC] activation=\(activationState.rawValue) err=\(error?.localizedDescription ?? "-")")
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handlePhonePayload(message)
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handlePhonePayload(userInfo)
    }

    private func handlePhonePayload(_ p: [String: Any]) {
        guard let cmd = p["cmd"] as? String else { return }
        switch cmd {
        case "start":
            let test = (p["test"] as? Bool) ?? false
            Task { await self.startWorkout(isTest: test) }
        case "stop":
            Task { await self.endWorkout() }
        default: break
        }
    }
}

// MARK: - App delegate

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        // Reserved for HKWorkoutSession mirroring from iPhone; not used here.
        // The iPhone drives start/stop via WatchConnectivity instead.
    }
}
