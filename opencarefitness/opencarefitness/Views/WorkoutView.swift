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

    // MARK: - Chart Panel

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isPad {
                // Header: Spacious single-line layout for iPad
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROFIL & TÉLÉMÉTRIE")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .tracking(2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            Picker("Metric", selection: $selectedMetric) {
                                ForEach(ChartMetric.allCases) { metric in
                                    Text(metric.rawValue).tag(metric)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 300)

                            Label("Projection", systemImage: "square.fill")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Incline display
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("PENTE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", engine.currentIncline))
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .neonGlow(.neonCyan)
                            Text("%")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                // Header: Compact two-line layout for iPhone
                VStack(spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("PROFIL & TÉLÉMÉTRIE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("PENTE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", engine.currentIncline))
                                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                                    .neonGlow(.neonCyan)
                                Text("%")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        Label("Projection", systemImage: "square.fill")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.3))

                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(ChartMetric.allCases) { metric in
                                Text(metric.rawValue).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }

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
            // iPad: Horizontal Grid layout (under chart)
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
            // iPhone: Distributed vertical layout (spread to edges, space in middle)
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

    // MARK: - Footer Controls

    private var footerControls: some View {
        HStack(spacing: 12) {
            // Stop button
            Button {
                showStopConfirm = true
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .frame(width: 56, height: 56)
                    .glassPanel(cornerRadius: 28)
            }
            .buttonStyle(.plain)

            // Override indicator
            if abs(engine.difficultyMultiplier - engine.difficulty.multiplier) > 0.01 {
                Button {
                    withAnimation { engine.resetOffset() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("RESET")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .glassPanel(cornerRadius: 28)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Pause / Resume
            Button {
                withAnimation {
                    if engine.isPaused {
                        engine.resume()
                    } else {
                        engine.pause()
                        // Safety: drop resistance to minimum when paused
                        ble.targetResistance = 1
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3)
                    Text(engine.isPaused ? "REPRENDRE" : "PAUSE")
                        .font(.subheadline.weight(.bold))
                        .tracking(2)
                }
                .foregroundStyle(engine.isPaused ? AnyShapeStyle(.black) : AnyShapeStyle(Color.neonYellow))
                .padding(.horizontal, 32)
                .frame(height: 56)
                .background(
                    engine.isPaused
                        ? AnyShapeStyle(Color.neonCyan)
                        : AnyShapeStyle(.clear)
                )
                .glassPanel(cornerRadius: 28)
                .overlay(
                    Capsule()
                        .stroke(
                            engine.isPaused ? Color.clear : Color.neonYellow.opacity(0.3),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Resistance Panel (Right Side)

    private var resistancePanel: some View {
        VStack(spacing: isPad ? 20 : 12) {
            // + Button
            Button {
                withAnimation(.easeOut(duration: 0.1)) {
                    engine.incrementIncline()
                }
            } label: {
                Text("+")
                    .font(.system(size: isPad ? 56 : 40, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassPanel(cornerRadius: 32)
            }
            .buttonStyle(HitButtonStyle())

            // Override status
            VStack(spacing: 2) {
                Text("OFFSET")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(abs(engine.difficultyMultiplier - engine.difficulty.multiplier) < 0.01 ? "OFF" : String(format: "x%.2f", engine.difficultyMultiplier))
                    .font(.system(size: isPad ? 14 : 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(abs(engine.difficultyMultiplier - engine.difficulty.multiplier) < 0.01 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.neonCyan))
            }
            .padding(.vertical, 4)

            // - Button
            Button {
                withAnimation(.easeOut(duration: 0.1)) {
                    engine.decrementIncline()
                }
            } label: {
                Text("−")
                    .font(.system(size: isPad ? 56 : 40, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassPanel(cornerRadius: 32)
            }
            .buttonStyle(HitButtonStyle())
        }
        .padding(.vertical, 20)
        .padding(.horizontal, isPad ? 12 : 8)
        .padding(.trailing, isPad ? 0 : 44) // ON REPOUSSE LE TEXTE POUR PASSER L'ENCOCHE
        .frame(maxHeight: .infinity, alignment: .center)
        .background(
            Color.black.opacity(0.4)
                .ignoresSafeArea(.all, edges: .all)
        )
        .overlay(
            Group {
                if isPad {
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        )
    }
}

// MARK: - Hit Button Style (for sweaty-finger tapping)

struct HitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
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
