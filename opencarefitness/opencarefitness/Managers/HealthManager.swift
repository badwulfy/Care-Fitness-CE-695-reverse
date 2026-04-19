//
//  HealthManager.swift
//  opencarefitness
//
//  Manages HealthKit integration:
//  - iPhone authorization and workout summary saving
//  - launching the companion watchOS workout
//  - receiving mirrored Apple Watch heart-rate data
//

import Foundation

#if canImport(HealthKit) && os(iOS)
import HealthKit

@Observable
final class HealthManager: NSObject {

    var isAuthorized: Bool = false
    var watchHeartRate: Int = 0
    var isWorkoutActive: Bool = false
    var liveHeartRateStatusMessage: String?

    private let store = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?

    override init() {
        super.init()
        liveHeartRateStatusMessage = "Prêt à démarrer le workout sur l’Apple Watch."
        configureMirroringHandler()
        Task { await checkAuthorization() }
    }

    // MARK: - Authorization

    func checkAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[HealthKit] ❌ Données de santé non disponibles sur cet appareil.")
            return
        }

        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let workoutType = HKObjectType.workoutType()

        let hrStatus = store.authorizationStatus(for: hrType)
        let workoutStatus = store.authorizationStatus(for: workoutType)

        print("[HealthKit] 🔍 Diagnostic des permissions :")
        print("   - Statut Rythme Cardiaque : \(hrStatus.rawValue)")
        print("   - Statut Entraînements : \(workoutStatus.rawValue)")

        await MainActor.run {
            self.isAuthorized = (workoutStatus == .sharingAuthorized)
            print("   - Résultat final isAuthorized : \(self.isAuthorized)")
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
            await checkAuthorization()
        } catch {
            print("[HealthKit] Authorization failed: \(error)")
            await MainActor.run {
                self.liveHeartRateStatusMessage = "Autorisation Santé refusée: \(error.localizedDescription)"
            }
            await checkAuthorization()
        }
    }

    // MARK: - Mirrored Workout

    func startWorkout() async {
        print("[HealthKit] ⌚️ Demande de démarrage du workout sur Apple Watch...")
        await checkAuthorization()

        if !isAuthorized {
            await requestAuthorization()
            await checkAuthorization()
        }

        guard isAuthorized else {
            await MainActor.run {
                liveHeartRateStatusMessage = "Autorise Santé sur l’iPhone avant de lancer la montre."
            }
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .elliptical
        configuration.locationType = .indoor

        do {
            try await store.startWatchApp(toHandle: configuration)
            await MainActor.run {
                self.isWorkoutActive = true
                self.watchHeartRate = 0
                self.liveHeartRateStatusMessage = "Apple Watch réveillée. En attente de la fréquence cardiaque..."
            }
        } catch {
            print("[HealthKit] Failed to start watch app: \(error)")
            await MainActor.run {
                self.isWorkoutActive = false
                self.liveHeartRateStatusMessage = "Impossible de lancer l’Apple Watch: \(error.localizedDescription)"
            }
        }
    }

    func endWorkout() async {
        print("[HealthKit] ⌚️ Fin du workout miroir côté iPhone...")

        if let mirroredSession {
            mirroredSession.end()
        }

        await MainActor.run {
            self.mirroredSession = nil
            self.isWorkoutActive = false
            self.watchHeartRate = 0
            self.liveHeartRateStatusMessage = "Workout arrêté."
        }
    }

    private func configureMirroringHandler() {
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            guard let self else { return }
            print("[HealthKit] 📲 Session miroir reçue depuis l’Apple Watch.")

            session.delegate = self

            Task { @MainActor in
                self.mirroredSession = session
                self.isWorkoutActive = true
                self.liveHeartRateStatusMessage = "Session miroir connectée à l’Apple Watch."
            }
        }
    }

    private func applyHeartRatePayload(_ data: Data) {
        do {
            let payload = try JSONDecoder().decode(HeartRatePayload.self, from: data)
            Task { @MainActor in
                self.watchHeartRate = payload.heartRate
                self.isWorkoutActive = true
                self.liveHeartRateStatusMessage = nil
            }
        } catch {
            print("[HealthKit] Failed to decode mirrored HR payload: \(error)")
        }
    }

    // MARK: - Save Summary

    func saveWorkoutSummary(
        duration: TimeInterval,
        calories: Double,
        distance: Double
    ) async {
        guard isAuthorized else { return }

        let start = Date().addingTimeInterval(-duration)
        let end = Date()

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

        do {
            try await store.save(workout)
        } catch {
            print("[HealthKit] Failed to save workout: \(error)")
        }
    }
}

extension HealthManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        print("[HealthKit] 🔄 Session miroir : \(fromState.rawValue) -> \(toState.rawValue)")

        Task { @MainActor in
            self.isWorkoutActive = (toState == .running)
            if toState == .ended || toState == .stopped {
                self.watchHeartRate = 0
                self.liveHeartRateStatusMessage = "Session miroir terminée."
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.isWorkoutActive = false
            self.liveHeartRateStatusMessage = "Session miroir en erreur: \(error.localizedDescription)"
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        Task { @MainActor in
            self.mirroredSession = nil
            self.isWorkoutActive = false
            self.watchHeartRate = 0
            self.liveHeartRateStatusMessage = error.map {
                "Apple Watch déconnectée: \($0.localizedDescription)"
            } ?? "Apple Watch déconnectée."
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for chunk in data {
            applyHeartRatePayload(chunk)
        }
    }
}

private struct HeartRatePayload: Codable {
    let heartRate: Int
}

#else

@Observable
final class HealthManager {
    var isAuthorized: Bool = false
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
