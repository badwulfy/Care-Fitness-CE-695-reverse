//
//  HealthManager.swift
//  opencarefitness
//
//  Manages HealthKit integration: workout sessions with Apple Watch
//  heart rate support, calorie/distance writing, and workout summaries.
//
//  On iOS: full HealthKit + HKWorkoutSession (triggers Apple Watch HR monitoring)
//  On macOS: stubbed out (HealthKit not available)
//

import Foundation

#if canImport(HealthKit) && os(iOS)
import HealthKit

@Observable
final class HealthManager {

    var isAuthorized: Bool = false
    var watchHeartRate: Int = 0  // HR from Apple Watch via HKWorkoutSession
    var isWorkoutActive: Bool = false

    private let store = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?

    init() {
        Task { await checkAuthorization() }
    }

    // MARK: - Authorization

    /// Vérifie silencieusement le statut d'autorisation existant sans afficher de dialog.
    func checkAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let status = store.authorizationStatus(for: hrType)
        await MainActor.run {
            isAuthorized = (status == .sharingAuthorized)
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
            isAuthorized = true
        } catch {
            print("[HealthKit] Authorization failed: \(error)")
        }
    }

    // MARK: - Workout Session (triggers Apple Watch HR)

    func startWorkout() async {
        guard isAuthorized else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .elliptical
        config.locationType = .indoor

        do {
            workoutSession = try HKWorkoutSession(healthStore: store, configuration: config)
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()
            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: store,
                workoutConfiguration: config
            )

            workoutSession?.startActivity(with: .now)
            try await workoutBuilder?.beginCollection(at: .now)
            isWorkoutActive = true

            startHeartRateObserver()
        } catch {
            print("[HealthKit] Failed to start workout: \(error)")
        }
    }

    func endWorkout() async {
        guard isWorkoutActive else { return }

        workoutSession?.end()
        stopHeartRateObserver()

        do {
            try await workoutBuilder?.endCollection(at: .now)
            try await workoutBuilder?.finishWorkout()
        } catch {
            print("[HealthKit] Failed to end workout: \(error)")
        }

        isWorkoutActive = false
        workoutSession = nil
        workoutBuilder = nil
    }

    // MARK: - Heart Rate Observer

    private func startHeartRateObserver() {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }

        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: HKQuery.predicateForSamples(withStart: .now, end: nil),
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }

        store.execute(query)
        heartRateQuery = query
    }

    private func stopHeartRateObserver() {
        if let query = heartRateQuery {
            store.stop(query)
            heartRateQuery = nil
        }
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let latest = quantitySamples.last else { return }

        let hr = Int(latest.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
        Task { @MainActor in
            self.watchHeartRate = hr
        }
    }

    // MARK: - Save Summary

    func saveWorkoutSummary(
        duration: TimeInterval,
        calories: Double,
        distance: Double // in meters
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

#else

// macOS stub — HealthKit not available
@Observable
final class HealthManager {
    var isAuthorized: Bool = false
    var watchHeartRate: Int = 0
    var isWorkoutActive: Bool = false

    func requestAuthorization() async { }
    func startWorkout() async { }
    func endWorkout() async { }
    func saveWorkoutSummary(duration: TimeInterval, calories: Double, distance: Double) async { }
}

#endif
