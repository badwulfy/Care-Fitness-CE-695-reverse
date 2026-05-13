//
//  HealthManager.swift
//  opencarefitness
//
//  - iPhone HealthKit authorization + workout summary persistence
//  - Live heart-rate stream from the paired Apple Watch via WatchConnectivity
//
//  Why WatchConnectivity (not HKWorkoutSession mirroring): the Watch records
//  its own elliptical workout in Health (with full HR samples). We only need
//  the live HR value here for display. WC is decoupled, debuggable, and avoids
//  duplicating workouts across devices.
//

import Foundation

#if canImport(HealthKit) && os(iOS)
import HealthKit
import WatchConnectivity

@Observable
final class HealthManager: NSObject {

    // Public state consumed by the UI
    var isAuthorized: Bool = false
    var isPermissionDenied: Bool = false
    var watchHeartRate: Int = 0
    var isWorkoutActive: Bool = false
    var liveHeartRateStatusMessage: String?

    private let store = HKHealthStore()
    private var wcSession: WCSession?
    /// True once a Watch HR sample has arrived in the current session. If true
    /// we skip the iPhone-side `HKWorkout` save to avoid duplicating the
    /// Watch's own workout in Apple Health.
    private var watchProvidedHR: Bool = false
    /// Set when the current session was launched as a test (Settings) — we
    /// suppress the iPhone summary unconditionally.
    private var suppressSummary: Bool = false

    override init() {
        super.init()
        liveHeartRateStatusMessage = "Ouvre l’app sur ta montre pour mesurer ton rythme cardiaque."
        Task { await checkAuthorization() }
        activateWatchConnectivity()
    }

    // MARK: - Authorization

    func checkAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let workoutStatus = store.authorizationStatus(for: HKObjectType.workoutType())
        await MainActor.run {
            self.isAuthorized      = (workoutStatus == .sharingAuthorized)
            self.isPermissionDenied = (workoutStatus == .sharingDenied)
            if self.isPermissionDenied {
                self.liveHeartRateStatusMessage =
                    "Accès Entraînements Santé refusé. Active l’accès dans Réglages."
            }
        }
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.workoutType()
        ]
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.workoutType()
        ]

        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        } catch {
            print("[HealthKit] Authorization failed: \(error)")
        }
        await checkAuthorization()
    }

    // MARK: - Workout lifecycle (iPhone-driven)

    /// Tells the Watch companion to start an HKWorkoutSession. Safe to call
    /// even if the Watch isn’t reachable — UI shows a hint, BLE HR keeps
    /// working as fallback.
    ///
    /// `isTest == true` (Settings → "Lancer le Test") starts the session for
    /// HR display only: the Watch will discard its workout on stop instead of
    /// persisting it, and the iPhone won't save its summary either.
    func startWorkout(isTest: Bool = false) async {
        await checkAuthorization()
        await MainActor.run {
            self.watchHeartRate = 0
            self.watchProvidedHR = false
            self.isWorkoutActive = false
            // Treat the test session like Watch-provided so saveWorkoutSummary
            // is suppressed too, even if no HR ever arrives.
            self.suppressSummary = isTest
        }
        sendToWatch(["cmd": "start", "test": isTest])
        await MainActor.run {
            if let s = wcSession, s.isReachable {
                liveHeartRateStatusMessage = "Demande envoyée à la montre…"
            } else {
                liveHeartRateStatusMessage =
                    "Montre non détectée. Ouvre l’app sur ta montre pour activer le suivi cardiaque."
            }
        }
    }

    func endWorkout() async {
        sendToWatch(["cmd": "stop"])
        await MainActor.run {
            self.isWorkoutActive = false
            self.watchHeartRate = 0
            self.liveHeartRateStatusMessage = "Séance arrêtée."
        }
    }

    // MARK: - Save Summary

    /// Saves an HKWorkout summary built from bike telemetry. Skipped when the
    /// Watch already recorded the same session (it owns the canonical workout
    /// with HR samples). Falls back to summary-only otherwise.
    func saveWorkoutSummary(
        duration: TimeInterval,
        calories: Double,
        distance: Double
    ) async {
        guard isAuthorized else { return }
        guard !watchProvidedHR, !suppressSummary else {
            print("[HealthKit] Skipping iPhone summary (watchProvidedHR=\(watchProvidedHR), suppress=\(suppressSummary)).")
            return
        }

        let end = Date()
        let start = end.addingTimeInterval(-duration)

        let workout = HKWorkout(
            activityType: .elliptical,
            start: start,
            end: end,
            duration: duration,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: distance),
            device: nil,
            metadata: ["Source": "OpenCareFitness"]
        )
        do { try await store.save(workout) }
        catch { print("[HealthKit] Failed to save workout: \(error)") }
    }

    // MARK: - WatchConnectivity

    private func activateWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        wcSession = s
    }

    private func sendToWatch(_ payload: [String: Any]) {
        guard let s = wcSession, s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil) { err in
                print("[WC] sendMessage failed: \(err.localizedDescription)")
            }
        } else {
            // Queue for later delivery; Watch will pick it up on next foreground.
            s.transferUserInfo(payload)
        }
    }
}

extension HealthManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("[WC] activation=\(activationState.rawValue) err=\(error?.localizedDescription ?? "-") paired=\(session.isPaired) installed=\(session.isWatchAppInstalled)")
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate to support multi-watch pairing changes.
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        // No UI alert: HR keeps streaming via applicationContext when the
        // Watch backgrounds (screen off), so dropping reachability is normal.
    }

    /// HR samples and state updates arriving from the Watch.
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleWatchPayload(message)
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleWatchPayload(userInfo)
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleWatchPayload(applicationContext)
    }

    private func handleWatchPayload(_ p: [String: Any]) {
        Task { @MainActor in
            if let hr = p["hr"] as? Int, hr > 0 {
                self.watchHeartRate = hr
                self.watchProvidedHR = true
                self.isWorkoutActive = true
                self.liveHeartRateStatusMessage = nil
            }
            if let state = p["state"] as? String {
                switch state {
                case "started":
                    self.isWorkoutActive = true
                    self.liveHeartRateStatusMessage = "Mesure cardiaque active sur la montre."
                case "ended":
                    self.isWorkoutActive = false
                    self.watchHeartRate = 0
                case "error":
                    let msg = (p["message"] as? String) ?? "Erreur côté montre."
                    self.liveHeartRateStatusMessage = msg
                    self.isWorkoutActive = false
                default: break
                }
            }
        }
    }
}

#else

@Observable
final class HealthManager {
    var isAuthorized: Bool = false
    var isPermissionDenied: Bool = false
    var watchHeartRate: Int = 0
    var isWorkoutActive: Bool = false
    var liveHeartRateStatusMessage: String? =
        "HealthKit n'est pas disponible sur cette plateforme."

    func requestAuthorization() async { }
    func startWorkout() async { }
    func endWorkout() async { }
    func saveWorkoutSummary(duration: TimeInterval, calories: Double, distance: Double) async { }
}

#endif
