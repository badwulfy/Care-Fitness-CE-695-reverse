//
//  WorkoutSessionManager.swift
//  opencarefitness
//
//  Coordinates the workout lifecycle between BluetoothManager, 
//  PatternEngine, and HealthManager.
//

import SwiftUI
import SwiftData

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
        
        bleManager.targetResistance = engine.currentResistance
        engine.start()
        
        Task { await healthManager.startWorkout() }
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
        
        #if os(iOS)
        Task {
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
    }
}
