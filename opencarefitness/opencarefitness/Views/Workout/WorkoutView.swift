//
//  WorkoutView.swift
//  opencarefitness
//
//  Active workout dashboard: chart, metrics grid, +/- controls, footer.
//  Designed for sweaty-finger usability with huge tap targets.
//

import SwiftUI
import Combine

struct WorkoutView: View {
    @Environment(BluetoothManager.self) private var ble
    @Environment(PatternEngine.self) private var engine
    @Environment(HealthManager.self) private var health
    
    var onStop: () -> Void

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    @State private var powerHistory: [Double] = []
    @State private var speedHistory: [Double] = []
    @State private var rpmHistory: [Double] = []
    @State private var showStopConfirm = false
    @State private var inactiveSeconds: Int = 0

    enum ChartMetric: String, CaseIterable, Identifiable {
        case power = "Puissance"
        case speed = "Vitesse"
        case rpm = "RPM"
        var id: String { rawValue }
    }
    @State private var selectedMetric: ChartMetric = .power

    // Prefer Apple Watch HR, fallback to machine HR
    private var displayedHR: Int {
        if health.watchHeartRate > 0 {
            return health.watchHeartRate
        }
        if Date().timeIntervalSince(ble.telemetry.lastUpdate) < 10.0 {
            return ble.telemetry.heartRate
        }
        return 0
    }

    private var hrSource: String {
        health.watchHeartRate > 0 ? "⌚" : "🏋️"
    }

    var body: some View {
        Group {
            if isPad {
                // MARK: - iPad Layout (Restored from commit bf94dc3)
                HStack(spacing: 0) {
                    VStack(spacing: 20) {
                        chartPanel
                            .frame(maxHeight: .infinity)
                        
                        metricsGrid
                            .padding(.bottom, 8)
                        
                        footerControls
                            .frame(height: 64)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)

                    resistancePanel
                        .frame(width: 160)
                }
            } else {
                // MARK: - iPhone Layout (Current perfect layout)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        chartPanel
                            .frame(maxHeight: .infinity)
                            .padding(.bottom, 16)

                        footerControls
                            .frame(height: 56)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)

                    metricsGrid
                        .padding(.vertical, 12)
                        .frame(width: 280)

                    resistancePanel
                        .frame(width: 130)
                }
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
            }
        }
        .onChange(of: engine.currentResistance) { _, newValue in
            ble.targetResistance = newValue
        }
        .onChange(of: ble.telemetry.watts) { _, newWatts in
            let powerNorm = min(1.0, Double(newWatts) / 300.0)
            let speedNorm = min(1.0, ble.telemetry.speedKmh / 40.0)
            let rpmNorm = min(1.0, Double(ble.telemetry.rpm) / 120.0)

            powerHistory.append(powerNorm)
            speedHistory.append(speedNorm)
            rpmHistory.append(rpmNorm)

            if powerHistory.count > 40 {
                powerHistory.removeFirst()
                speedHistory.removeFirst()
                rpmHistory.removeFirst()
            }
        }
        .confirmationDialog(
            "Arrêter l'exercice ?",
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button("Arrêter", role: .destructive) { onStop() }
            Button("Annuler", role: .cancel) { }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard engine.isRunning else { return }
            
            let isStale = Date().timeIntervalSince(ble.telemetry.lastUpdate) > 5.0
            let isStopped = ble.telemetry.rpm == 0 && ble.telemetry.speedKmh == 0 && ble.telemetry.watts == 0
            
            if isStopped || isStale {
                inactiveSeconds += 1
                if inactiveSeconds >= 5 && !engine.isPaused {
                    withAnimation { engine.pause() }
                }
            } else {
                inactiveSeconds = 0
                if engine.isPaused {
                    withAnimation { engine.resume() }
                }
            }
        }
        .background(Color.appBackground)
        .forceOrientationOnPhone(.landscape)
    }

    // MARK: - Subviews

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkoutHeader(selectedMetric: $selectedMetric, isPad: isPad)

            // Chart
            PatternChartView(
                pattern: engine.selectedPattern,
                progress: engine.progress,
                currentWatts: ble.telemetry.watts,
                wattsHistory: selectedMetric == .power ? powerHistory : (selectedMetric == .speed ? speedHistory : rpmHistory),
                difficultyMultiplier: engine.difficultyMultiplier
            )

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Color.neonCyan)
                        .frame(width: geo.size.width * engine.progress)
                }
            }
            .frame(height: 4)
        }
        .padding(20)
        .glassPanel(cornerRadius: 32)
    }

    private var metricsGrid: some View {
        let tel = ble.telemetry
        
        if isPad {
            return AnyView(
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        MetricCard(title: "PULSE \(hrSource)", value: displayedHR > 0 ? "\(displayedHR)" : "--", unit: "bpm", color: .neonRed, icon: "heart.fill", isLarge: true)
                        MetricCard(title: "PUISSANCE", value: "\(tel.watts)", unit: "W", color: .neonYellow, isLarge: true)
                        MetricCard(title: "CHRONOMÈTRE", value: engine.formattedElapsed, unit: engine.goalType == .duration ? "/ \(engine.formattedGoalDuration)" : "", color: .white, isLarge: true)
                    }
                    GridRow {
                        MetricCard(title: "CADENCE", value: "\(tel.rpm)", unit: "RPM", color: .neonCyan, isLarge: true)
                        MetricCard(title: "VITESSE", value: String(format: "%.1f", tel.speedKmh), unit: "km/h", color: .neonGreen, isLarge: true)
                        MetricCard(title: "DISTANCE", value: String(format: "%.2f", Double(tel.distance) / 1000.0), unit: "km", color: .neonBlue, isLarge: true)
                    }
                }
            )
        } else {
            let hSpacing: CGFloat = 12
            return AnyView(
                VStack(spacing: 12) {
                    HStack(spacing: hSpacing) {
                        MetricCard(title: "Pulse \(hrSource)", value: displayedHR > 0 ? "\(displayedHR)" : "--", unit: "bpm", color: .neonRed, icon: "heart.fill", isLarge: false)
                        MetricCard(title: "Chrono", value: engine.formattedElapsed, unit: "", color: .white, isLarge: false)
                    }
                    .frame(height: 85)
                    
                    HStack(spacing: hSpacing) {
                        MetricCard(title: "Puiss.", value: "\(tel.watts)", unit: "W", color: .neonYellow, isLarge: false)
                        MetricCard(title: "Cadence", value: "\(tel.rpm)", unit: "RPM", color: .neonCyan, isLarge: false)
                    }
                    .frame(height: 85)
                    .frame(maxHeight: .infinity)
                    
                    HStack(spacing: hSpacing) {
                        MetricCard(title: "Vitesse", value: String(format: "%.1f", tel.speedKmh), unit: "km/h", color: .neonGreen, isLarge: false)
                        MetricCard(title: "Énergie", value: "\(tel.calories)", unit: "kcal", color: .neonOrange, isLarge: false)
                    }
                    .frame(height: 85)
                }
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
            )
        }
    }

    private var footerControls: some View {
        WorkoutControls(showStopConfirm: $showStopConfirm)
    }

    private var resistancePanel: some View {
        ResistancePanel(isPad: isPad)
    }
}

// MARK: - Previews

private func createMockBLE() -> BluetoothManager {
    let ble = BluetoothManager()
    ble.telemetry.watts = 185
    ble.telemetry.rpm = 65
    ble.telemetry.speedKmh = 24.5
    ble.telemetry.distance = 420
    ble.telemetry.calories = 115
    ble.telemetry.heartRate = 142
    return ble
}

#Preview("Workout Dashboard") {
    let engine = PatternEngine()
    engine.selectedPattern = .pyramid
    engine.goalDurationSeconds = 2700
    engine.start()

    return WorkoutView(onStop: { })
        .environment(createMockBLE())
        .environment(engine)
        .environment(HealthManager())
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
}

#Preview("Workout — iPad", traits: .landscapeLeft) {
    let engine = PatternEngine()
    engine.selectedPattern = .hiit
    engine.goalDurationSeconds = 1800
    engine.start()

    return WorkoutView(onStop: { })
        .environment(createMockBLE())
        .environment(engine)
        .environment(HealthManager())
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
}
