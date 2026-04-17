//
//  ContentView.swift
//  opencarefitness
//
//  Root view: navigation between Setup → Workout → Summary screens.
//  Manages lifecycle, BLE connection, and background safety.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
import SwiftData

// MARK: - App Screen

enum AppScreen: Equatable {
    case setup
    case workout
    case summary
    case history
}

// MARK: - Content View

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var screen: AppScreen = .setup
    @State private var bleManager = BluetoothManager()
    @State private var engine = PatternEngine()
    @State private var healthManager = HealthManager()

    // Workout stats accumulation
    @State private var hrSamples: [Int] = []
    @State private var wattsSamples: [Int] = []
    @State private var rpmSamples: [Int] = []
    @State private var maxWatts: Int = 0
    @State private var maxHR: Int = 0
    @State private var maxIncline: Double = 0

    // Summary session for the summary screen
    @State private var lastSession: WorkoutSession?

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Bar
            topBar
                .frame(height: 52)

            // MARK: - Main Content
            Group {
                switch screen {
                case .setup:
                    SetupView(
                        engine: engine,
                        bleManager: bleManager,
                        onStart: startWorkout
                    )

                case .workout:
                    WorkoutView(
                        bleManager: bleManager,
                        engine: engine,
                        healthManager: healthManager,
                        onStop: stopWorkout
                    )

                case .summary:
                    if let session = lastSession {
                        SummaryView(
                            session: session,
                            healthManager: healthManager,
                            onDismiss: { withAnimation { screen = .setup } }
                        )
                    }

                case .history:
                    HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
        .task {
            await healthManager.requestAuthorization()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        // Update stats while working out
        .onChange(of: bleManager.telemetry.heartRate) { _, hr in
            guard screen == .workout, hr > 0 else { return }
            hrSamples.append(hr)
            maxHR = max(maxHR, hr)
        }
        .onChange(of: bleManager.telemetry.watts) { _, w in
            guard screen == .workout else { return }
            wattsSamples.append(w)
            maxWatts = max(maxWatts, w)
        }
        .onChange(of: bleManager.telemetry.rpm) { _, r in
            guard screen == .workout, r > 0 else { return }
            rpmSamples.append(r)
        }
        .onChange(of: engine.currentIncline) { _, incline in
            maxIncline = max(maxIncline, incline)
        }
        .onChange(of: engine.isGoalReached) { _, reached in
            if reached && screen == .workout {
                stopWorkout()
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Logo
            HStack(spacing: 0) {
                Text("CARE")
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.9))
                Text("TRAINER")
                    .fontWeight(.bold)
                    .foregroundStyle(Color.neonCyan)
            }
            .font(.title2)
            .tracking(2)

            // Nav tabs (only visible when not in workout)
            if screen != .workout {
                Spacer()

                HStack(spacing: 4) {
                    NavTab(title: "SETUP", isActive: screen == .setup) {
                        withAnimation { screen = .setup }
                    }
                    NavTab(title: "HISTORIQUE", isActive: screen == .history) {
                        withAnimation { screen = .history }
                    }
                }
                .padding(4)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }

            Spacer()

            // BLE status
            HStack(spacing: 12) {
                BLEStatusBadge(state: bleManager.connectionState)

                if bleManager.connectionState == .disconnected || bleManager.connectionState == .error {
                    Button {
                        bleManager.startScanning()
                    } label: {
                        Text("Connecter")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.neonCyan.opacity(0.2))
                            .foregroundStyle(Color.neonCyan)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Button {
                            bleManager.disconnect()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                bleManager.startScanning()
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.bold))
                                .padding(6)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Forcer la reconnexion")

                        Button {
                            bleManager.disconnect()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .padding(6)
                                .background(Color.red.opacity(0.2))
                                .foregroundStyle(.red)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Déconnecter")
                    }
                }

                DeviceBatteryView()

                // Clock
                Text(Date.now, format: .dateTime.hour().minute())
                    .font(.body.weight(.medium).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .background(Color(red: 0.03, green: 0.05, blue: 0.09))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Workout Lifecycle

    private func startWorkout() {
        // Reset accumulators
        hrSamples = []
        wattsSamples = []
        rpmSamples = []
        maxWatts = 0
        maxHR = 0
        maxIncline = 0

        // Set initial resistance
        bleManager.targetResistance = engine.currentResistance

        // Start engine
        engine.start()

        // Start HealthKit workout session (iOS, activates Apple Watch)
        Task {
            await healthManager.startWorkout()
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            screen = .workout
        }
    }

    private func stopWorkout() {
        engine.stop()

        // Safety: reset to minimum resistance
        bleManager.targetResistance = 1

        // End HealthKit session
        Task {
            await healthManager.endWorkout()
        }

        // Build session record
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

        // Save to SwiftData
        modelContext.insert(session)
        lastSession = session

        withAnimation(.easeInOut(duration: 0.3)) {
            screen = .summary
        }
    }

    // MARK: - Background Safety

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard screen == .workout else { return }
        switch phase {
        case .background, .inactive:
            // Safety: reduce resistance to minimum when app is backgrounded
            bleManager.targetResistance = 1
            if engine.isRunning && !engine.isPaused {
                engine.pause()
            }
        case .active:
            // Restore engine resistance when coming back
            bleManager.targetResistance = engine.currentResistance
        @unknown default:
            break
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case 75...: return "battery.100"
        case 50...: return "battery.75"
        case 25...: return "battery.50"
        default:    return "battery.25"
        }
    }
}

// MARK: - BLE Status Badge

private struct BLEStatusBadge: View {
    let state: BLEConnectionState

    private var dotColor: Color {
        switch state {
        case .connected:    return .green
        case .scanning, .connecting, .initializing: return .yellow
        case .disconnected: return .gray
        case .error:        return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .fill(dotColor.opacity(0.4))
                        .frame(width: 14, height: 14)
                        .opacity(state == .connected ? 1 : 0)
                )

            Text(state.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Nav Tab

private struct NavTab: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isActive ? Color.neonCyan.opacity(0.2) : Color.clear)
                .foregroundStyle(isActive ? Color.neonCyan : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Device Battery

private struct DeviceBatteryView: View {
    @State private var level: Int = -1

    var body: some View {
        HStack(spacing: 3) {
            if level >= 0 {
                Image(systemName: batteryIcon(level))
                    .font(.caption2)
                Text("\(level)%")
                    .font(.caption2.monospacedDigit())
            } else {
                Image(systemName: "battery.100")
                    .font(.caption2)
                Text("--%")
                    .font(.caption2.monospacedDigit())
            }
        }
        .foregroundStyle(.secondary)
        .onAppear {
            #if os(iOS)
            UIDevice.current.isBatteryMonitoringEnabled = true
            updateBattery()
            #endif
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            #if os(iOS)
            updateBattery()
            #endif
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case 75...: return "battery.100"
        case 50...: return "battery.75"
        case 25...: return "battery.50"
        default:    return "battery.25"
        }
    }

    #if os(iOS)
    private func updateBattery() {
        let raw = UIDevice.current.batteryLevel
        if raw >= 0 {
            self.level = Int(raw * 100)
        } else {
            self.level = -1
        }
    }
    #endif
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: WorkoutSession.self, inMemory: true)
}
