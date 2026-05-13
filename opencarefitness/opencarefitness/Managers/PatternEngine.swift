//
//  PatternEngine.swift
//  opencarefitness
//
//  Controls the workout flow: timer, pattern progression,
//  incline scheduling, and manual override (offset).
//

import Foundation

@Observable
final class PatternEngine {

    // MARK: - Configuration

    var selectedPattern: WorkoutPattern = .flat
    var goalType: WorkoutGoalType = .duration
    var goalDurationSeconds: Int = 2700   // 45 min default
    var goalDistanceHm: Int = 100         // 10 km default (hectometers)
    var difficulty: WorkoutDifficulty = .medium

    // MARK: - Runtime State

    var isRunning: Bool = false
    var isPaused: Bool = false
    var elapsedSeconds: Int = 0
    var currentDistanceHm: Int = 0          // Tracking distance for distance goals
    var difficultyMultiplier: Double = 1.0 // Dynamic coefficient applied on top of pattern
    /// Re-rolled on each `start()`. Makes the `random` pattern produce a fresh
    /// sequence per session while staying deterministic within the session.
    private var sessionSeed: UInt64 = 0

    // Computed
    var currentIncline: Double {
        let base = selectedPattern.incline(at: progress, multiplier: difficultyMultiplier, seed: sessionSeed)
        return min(32.0, max(0.0, base))
    }

    var currentResistance: Int {
        BluetoothManager.inclineToResistance(currentIncline)
    }

    var progress: Double {
        switch goalType {
        case .free:
            return 0.0 // No time-dilation in free mode
        case .duration:
            guard goalDurationSeconds > 0 else { return 0 }
            return min(1.0, Double(elapsedSeconds) / Double(goalDurationSeconds))
        case .distance:
            guard goalDistanceHm > 0 else { return 0 }
            return min(1.0, Double(currentDistanceHm) / Double(goalDistanceHm))
        }
    }

    var isGoalReached: Bool {
        switch goalType {
        case .free:     return false
        case .duration: return elapsedSeconds >= goalDurationSeconds
        case .distance: return currentDistanceHm >= goalDistanceHm
        }
    }

    var remainingSeconds: Int {
        switch goalType {
        case .duration: return max(0, goalDurationSeconds - elapsedSeconds)
        case .free, .distance: return 0
        }
    }

    var remainingDistanceHm: Int {
        switch goalType {
        case .distance: return max(0, goalDistanceHm - currentDistanceHm)
        case .free, .duration: return 0
        }
    }

    var formattedElapsed: String {
        formatTime(elapsedSeconds)
    }

    var formattedRemaining: String {
        formatTime(remainingSeconds)
    }

    var formattedGoalDuration: String {
        formatTime(goalDurationSeconds)
    }

    // MARK: - Timer

    private var timerTask: Task<Void, Never>?

    func start() {
        guard !isRunning else { return }
        elapsedSeconds = 0
        currentDistanceHm = 0
        difficultyMultiplier = difficulty.multiplier
        sessionSeed = UInt64.random(in: .min ... .max)
        isRunning = true
        isPaused = false
        resumeTimer()
    }

    func pause() {
        isPaused = true
        timerTask?.cancel()
    }

    func resume() {
        isPaused = false
        resumeTimer()
    }

    func stop() {
        isRunning = false
        isPaused = false
        timerTask?.cancel()
    }

    func incrementIncline() {
        // For flat (maxBaseIncline == 0) the multiplier has no visible effect.
        guard selectedPattern.maxBaseIncline > 0 else { return }
        let maxAllowed = 15.0 / selectedPattern.maxBaseIncline
        if difficultyMultiplier < maxAllowed {
            difficultyMultiplier = min(maxAllowed, difficultyMultiplier + 0.1)
        }
    }

    func decrementIncline() {
        difficultyMultiplier = max(0.1, difficultyMultiplier - 0.1)
    }

    func resetOffset() {
        difficultyMultiplier = difficulty.multiplier
    }

    // MARK: - Private

    private func resumeTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
