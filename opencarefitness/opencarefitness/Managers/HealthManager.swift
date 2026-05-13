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
    var isPermissionDenied: Bool = false
    var watchHeartRate: Int = 0
    var isWorkoutActive: Bool = false
    var liveHeartRateStatusMessage: String?

    private let store = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?

    // iPhone-side workout builder: collects granular samples (HR from bike BLE,
    // distance, calories) during the session and persists them on stop.
    private var localBuilder: HKWorkoutBuilder?
    private var localBuilderStart: Date?

    override init() {
        super.init()
        liveHeartRateStatusMessage = "Prêt à démarrer le workout sur l’Apple Watch."
        configureMirroringHandler()
        Task { 
            await checkAuthorization() 
            await recoverActiveWorkoutSession() // Tente de récupérer une session déjà en cours
        }
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
            // Pour l'iPhone, on a surtout besoin de pouvoir "Partager" (écrire) l'Entraînement pour enregistrer le résumé.
            self.isAuthorized = (workoutStatus == .sharingAuthorized)
            
            // Pour le rythme cardiaque, l'iPhone ne fait que LIRE. 
            // 'sharingDenied' (1) signifie qu'on ne peut pas ÉCRIRE, ce qui n'est pas bloquant pour le mirroring.
            // On ne considère donc comme "Erreur Critique" que si l'accès aux Entraînements est refusé.
            self.isPermissionDenied = (workoutStatus == .sharingDenied)
            
            if self.isPermissionDenied {
                self.liveHeartRateStatusMessage = "Accès Entraînements Santé refusé. Active l'accès dans les Réglages iPhone."
            } else if hrStatus == .sharingDenied {
                print("[HealthKit] Note: Accès ÉCRITURE rythme cardiaque refusé, mais la LECTURE est peut-être possible via Mirroring.")
            }
            
            print("   - Statut Final : Authorized=\(self.isAuthorized), PermissionDenied=\(self.isPermissionDenied)")
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

        // Local builder so we save granular samples even if the Apple Watch
        // companion never starts (or crashes mid-workout).
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let start = Date()
        do {
            try await builder.beginCollection(at: start)
            await MainActor.run {
                self.localBuilder = builder
                self.localBuilderStart = start
            }
        } catch {
            print("[HealthKit] beginCollection failed: \(error)")
        }

        do {
            try await store.startWatchApp(toHandle: configuration)
            await MainActor.run {
                self.watchHeartRate = 0
                self.liveHeartRateStatusMessage = "Signal d’éveil envoyé à l’Apple Watch..."
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

    // MARK: - Live samples (bike BLE → HealthKit)

    /// Append one HR sample to the local builder. No-op if HealthKit is denied
    /// or the builder failed to start. Power isn't meaningful for `.elliptical`
    /// in Health so we don't record it here.
    func recordSample(heartRate: Int, distanceMeters: Double, calories: Double, watts: Int) async {
        guard let builder = localBuilder, heartRate > 0 else { return }
        let now = Date()
        let hrType = HKQuantityType(.heartRate)
        let quantity = HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: Double(heartRate))
        let sample = HKQuantitySample(type: hrType, quantity: quantity, start: now, end: now)
        do { try await builder.addSamples([sample]) }
        catch { print("[HealthKit] addSamples failed: \(error)") }
    }

    /// Finalize the iPhone-side workout: stamps totals, closes the builder.
    /// Falls back to the legacy `saveWorkoutSummary` path if the builder never
    /// started (e.g. permission denied at session start).
    func finalizeLocalWorkout(duration: TimeInterval, calories: Double, distance: Double) async {
        guard let builder = localBuilder, let start = localBuilderStart else {
            await saveWorkoutSummary(duration: duration, calories: calories, distance: distance)
            return
        }
        let end = start.addingTimeInterval(duration)

        var totalSamples: [HKQuantitySample] = []
        if calories > 0,
           let kcalType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            totalSamples.append(HKQuantitySample(
                type: kcalType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                start: start, end: end))
        }
        if distance > 0,
           let distType = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            totalSamples.append(HKQuantitySample(
                type: distType,
                quantity: HKQuantity(unit: .meter(), doubleValue: distance),
                start: start, end: end))
        }

        do {
            if !totalSamples.isEmpty { try await builder.addSamples(totalSamples) }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            print("[HealthKit] finishWorkout failed: \(error)")
        }

        await MainActor.run {
            self.localBuilder = nil
            self.localBuilderStart = nil
        }
    }

    private func configureMirroringHandler() {
        print("[HealthKit] 🔧 Enregistrement du workoutSessionMirroringStartHandler...")
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            guard let self else { return }
            print("[HealthKit] 📲 Session miroir automatique reçue depuis l’Apple Watch.")

            self.attachToSession(session)
        }
    }

    private func recoverActiveWorkoutSession() async {
        print("[HealthKit] 🔍 Tentative de récupération d'une session active...")
        do {
            if let activeSession = try await store.recoverActiveWorkoutSession() {
                print("[HealthKit] 📲 Session active récupérée !")
                attachToSession(activeSession)
            }
        } catch {
            print("[HealthKit] ❌ Erreur récupération session active: \(error.localizedDescription)")
        }
    }

    private func attachToSession(_ session: HKWorkoutSession) {
        session.delegate = self
        let builder = session.associatedWorkoutBuilder()
        builder.delegate = self
        
        Task { @MainActor in
            self.mirroredSession = session
            self.isWorkoutActive = (session.state == .running)
            self.liveHeartRateStatusMessage = "Session miroir connectée."
            print("[HealthKit] ✅ Delegate attaché à la session et au builder.")
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

}

extension HealthManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)),
              let statistics = workoutBuilder.statistics(for: HKQuantityType(.heartRate)),
              let quantity = statistics.mostRecentQuantity() else {
            return
        }
        
        let heartRate = Int(quantity.doubleValue(for: .count().unitDivided(by: .minute())))
        Task { @MainActor in
            self.watchHeartRate = heartRate
            self.isWorkoutActive = true
            self.liveHeartRateStatusMessage = nil
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
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
    func recordSample(heartRate: Int, distanceMeters: Double, calories: Double, watts: Int) async { }
    func finalizeLocalWorkout(duration: TimeInterval, calories: Double, distance: Double) async { }
}

#endif
