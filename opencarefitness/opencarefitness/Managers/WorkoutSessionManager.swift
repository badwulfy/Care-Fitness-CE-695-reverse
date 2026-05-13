//
//  WorkoutSessionManager.swift
//  opencarefitness
//
//  Coordinates the workout lifecycle between BluetoothManager, 
//  PatternEngine, and HealthManager.
//

import SwiftUI
import SwiftData

/// Crash-safe snapshot of an in-progress session. Stored as JSON in
/// UserDefaults so the next launch can detect and persist a workout the
/// app died mid-way through.
private struct InFlightSessionSnapshot: Codable {
    var startedAt: Date
    var patternName: String
    var durationSeconds: Int
    var distanceTotal: Int
    var caloriesTotal: Int
    var avgHeartRate: Int
    var maxHeartRate: Int
    var avgWatts: Int
    var maxWatts: Int
    var avgRPM: Int
    var maxIncline: Double
    var updatedAt: Date
}

private enum SessionRecoveryKeys {
    static let snapshot = "wsm.inFlightSnapshot"
    static let throttle: TimeInterval = 5.0   // write at most every 5s
}

@Observable
final class WorkoutSessionManager {
    // References to other managers
    private let bleManager: BluetoothManager
    private let engine: PatternEngine
    private let healthManager: HealthManager

    // Session state
    var hrSamples: [Int] = []
    var wattsSamples: [Int] = []
    var rpmSamples: [Int] = []
    var maxWatts: Int = 0
    var maxHR: Int = 0
    var maxIncline: Double = 0

    var lastSession: WorkoutSession?

    private var lastSnapshotWrite: Date = .distantPast

    init(bleManager: BluetoothManager, engine: PatternEngine, healthManager: HealthManager) {
        self.bleManager = bleManager
        self.engine = engine
        self.healthManager = healthManager
    }
    
    func start() {
        hrSamples = []
        wattsSamples = []
        rpmSamples = []
        maxWatts = 0
        maxHR = 0
        maxIncline = 0
        lastSnapshotWrite = .distantPast

        engine.start()
        bleManager.targetResistance = engine.currentResistance

        Task { await healthManager.startWorkout() }
        writeSnapshot(force: true)
    }
    
    func stop(context: ModelContext) -> WorkoutSession {
        engine.stop()
        bleManager.targetResistance = 1
        
        Task { await healthManager.endWorkout() }
        
        let session = WorkoutSession(
            date: .now,
            patternName: engine.selectedPattern.rawValue,
            durationSeconds: engine.elapsedSeconds,
            distanceTotal: bleManager.telemetry.distance,
            caloriesTotal: bleManager.telemetry.calories,
            avgHeartRate: hrSamples.isEmpty ? 0 : hrSamples.reduce(0, +) / hrSamples.count,
            maxHeartRate: maxHR,
            avgWatts: wattsSamples.isEmpty ? 0 : wattsSamples.reduce(0, +) / wattsSamples.count,
            maxWatts: maxWatts,
            avgRPM: rpmSamples.isEmpty ? 0 : rpmSamples.reduce(0, +) / rpmSamples.count,
            maxIncline: maxIncline
        )
        
        context.insert(session)
        lastSession = session
        clearSnapshot()

        #if os(iOS)
        // Persist an iPhone-side HKWorkout summary (bike data). Skipped inside
        // HealthManager when the Watch already saved its own workout.
        Task { [healthManager, session] in
            await healthManager.saveWorkoutSummary(
                duration: Double(session.durationSeconds),
                calories: Double(session.caloriesTotal),
                distance: Double(session.distanceTotal) * 100
            )
        }
        #endif

        return session
    }

    func updateStats(hr: Int, watts: Int, rpm: Int, incline: Double) {
        if hr > 0 {
            hrSamples.append(hr)
            maxHR = max(maxHR, hr)
        }
        if watts >= 0 {
            wattsSamples.append(watts)
            maxWatts = max(maxWatts, watts)
        }
        if rpm > 0 {
            rpmSamples.append(rpm)
        }
        maxIncline = max(maxIncline, incline)

        writeSnapshot(force: false)
    }

    // MARK: - Crash recovery

    /// Persist a snapshot of the in-flight session so a crash mid-workout can
    /// still be saved on next launch. Throttled to once per ~5s.
    private func writeSnapshot(force: Bool) {
        guard engine.isRunning else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastSnapshotWrite) < SessionRecoveryKeys.throttle { return }
        lastSnapshotWrite = now

        let snapshot = InFlightSessionSnapshot(
            startedAt: now.addingTimeInterval(-Double(engine.elapsedSeconds)),
            patternName: engine.selectedPattern.rawValue,
            durationSeconds: engine.elapsedSeconds,
            distanceTotal: bleManager.telemetry.distance,
            caloriesTotal: bleManager.telemetry.calories,
            avgHeartRate: hrSamples.isEmpty ? 0 : hrSamples.reduce(0, +) / hrSamples.count,
            maxHeartRate: maxHR,
            avgWatts: wattsSamples.isEmpty ? 0 : wattsSamples.reduce(0, +) / wattsSamples.count,
            maxWatts: maxWatts,
            avgRPM: rpmSamples.isEmpty ? 0 : rpmSamples.reduce(0, +) / rpmSamples.count,
            maxIncline: maxIncline,
            updatedAt: now
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: SessionRecoveryKeys.snapshot)
        }
    }

    private func clearSnapshot() {
        UserDefaults.standard.removeObject(forKey: SessionRecoveryKeys.snapshot)
    }

    /// If a snapshot exists from a previous launch (= the app died mid-workout),
    /// turn it into a real WorkoutSession and persist it. Returns the recovered
    /// session if any was found.
    @discardableResult
    func recoverInFlightSessionIfNeeded(context: ModelContext) -> WorkoutSession? {
        guard let data = UserDefaults.standard.data(forKey: SessionRecoveryKeys.snapshot),
              let snap = try? JSONDecoder().decode(InFlightSessionSnapshot.self, from: data) else {
            return nil
        }
        // Discard implausibly short ghost snapshots (< 30s).
        guard snap.durationSeconds >= 30 else {
            clearSnapshot()
            return nil
        }

        let session = WorkoutSession(
            date: snap.startedAt,
            patternName: snap.patternName,
            durationSeconds: snap.durationSeconds,
            distanceTotal: snap.distanceTotal,
            caloriesTotal: snap.caloriesTotal,
            avgHeartRate: snap.avgHeartRate,
            maxHeartRate: snap.maxHeartRate,
            avgWatts: snap.avgWatts,
            maxWatts: snap.maxWatts,
            avgRPM: snap.avgRPM,
            maxIncline: snap.maxIncline
        )
        context.insert(session)
        clearSnapshot()
        return session
    }
}
