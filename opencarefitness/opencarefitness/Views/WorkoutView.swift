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
    var bleManager: BluetoothManager
    @Bindable var engine: PatternEngine
    var healthManager: HealthManager
    var onStop: () -> Void

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
        if healthManager.watchHeartRate > 0 {
            return healthManager.watchHeartRate
        }
        if Date().timeIntervalSince(bleManager.telemetry.lastUpdate) < 10.0 {
            return bleManager.telemetry.heartRate
        }
        return 0
    }

    private var hrSource: String {
        healthManager.watchHeartRate > 0 ? "⌚" : "🏋️"
    }

    var body: some View {
        HStack(spacing: 0) {

            // MARK: - Left: Chart + Metrics + Footer
            VStack(spacing: 16) {

                // MARK: Chart Panel
                chartPanel
                    .frame(maxHeight: .infinity)

                // MARK: Metrics Grid
                metricsGrid

                // MARK: Footer Controls
                footerControls
                    .frame(height: 56)
            }
            .padding(16)

            // MARK: - Right: Resistance Controls
            resistancePanel
                .frame(width: 140)
        }
        .onChange(of: engine.currentResistance) { _, newValue in
            bleManager.targetResistance = newValue
        }
        .onChange(of: bleManager.telemetry.watts) { _, newWatts in
            let powerNorm = min(1.0, Double(newWatts) / 300.0)
            let speedNorm = min(1.0, bleManager.telemetry.speedKmh / 40.0)
            let rpmNorm = min(1.0, Double(bleManager.telemetry.rpm) / 120.0)

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
            
            let isStale = Date().timeIntervalSince(bleManager.telemetry.lastUpdate) > 5.0
            
            if bleManager.telemetry.rpm == 0 || isStale {
                inactiveSeconds += 1
                if inactiveSeconds >= 3 && !engine.isPaused {
                    withAnimation { engine.pause() }
                }
            } else {
                inactiveSeconds = 0
                if engine.isPaused {
                    withAnimation { engine.resume() }
                }
            }
        }
    }

    // MARK: - Chart Panel

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PROFIL PENTE & DONNÉES EN DIRECT")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        Label("Pente", systemImage: "square.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.4))
                        
                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(ChartMetric.allCases) { metric in
                                Text(metric.rawValue).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }
                }

                Spacer()

                // Current incline display
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PENTE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", engine.currentIncline))
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .neonGlow(.neonCyan)
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Chart
            PatternChartView(
                pattern: engine.selectedPattern,
                progress: engine.progress,
                currentWatts: bleManager.telemetry.watts,
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
        .glassPanel()
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        let tel = bleManager.telemetry

        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MetricCard(
                    title: "Pulse \(hrSource)",
                    value: displayedHR > 0 ? "\(displayedHR)" : "--",
                    unit: "bpm",
                    color: .neonRed,
                    icon: "heart.fill"
                )

                MetricCard(
                    title: "Puissance",
                    value: "\(tel.watts)",
                    unit: "W",
                    color: .neonYellow
                )

                MetricCard(
                    title: "Chronomètre",
                    value: engine.formattedElapsed,
                    unit: engine.goalType == .duration ? "/ \(engine.formattedGoalDuration)" : "",
                    color: .white
                )
            }

            GridRow {
                MetricCard(
                    title: "Cadence",
                    value: "\(tel.rpm)",
                    unit: "RPM",
                    color: .neonCyan,
                    isLarge: false
                )

                MetricCard(
                    title: "Vitesse",
                    value: String(format: "%.1f", tel.speedKmh),
                    unit: "km/h",
                    color: .neonGreen,
                    isLarge: false
                )

                DualMetricCard(
                    leftTitle: "Distance",
                    leftValue: String(format: "%.1f", Double(tel.distance) / 100.0),
                    leftUnit: "km",
                    rightTitle: "Calories",
                    rightValue: "\(tel.calories)",
                    rightUnit: "kcal",
                    rightColor: .neonOrange
                )
            }
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
            }

            Spacer()

            // Pause / Resume
            Button {
                withAnimation {
                    if engine.isPaused {
                        engine.resume()
                    } else {
                        engine.pause()
                        // Safety: drop resistance to minimum when paused
                        bleManager.targetResistance = 1
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
        VStack(spacing: 12) {
            Text("CONTRÔLE")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(3)
                .foregroundStyle(.secondary)
                .padding(.top, 16)

            // + Button
            Button {
                withAnimation(.easeOut(duration: 0.1)) {
                    engine.incrementIncline()
                }
            } label: {
                Text("+")
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassPanel(cornerRadius: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.05), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
            .buttonStyle(HitButtonStyle())

            // Override status
            VStack(spacing: 4) {
                Text("OVERRIDE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Text(abs(engine.difficultyMultiplier - engine.difficulty.multiplier) < 0.01 ? "OFF" : String(format: "x%.2f", engine.difficultyMultiplier))
                    .font(.system(.body, design: .monospaced, weight: .bold))
                    .foregroundStyle(abs(engine.difficultyMultiplier - engine.difficulty.multiplier) < 0.01 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.neonCyan))
                    .contentTransition(.numericText())
            }
            .padding(.vertical, 8)

            // - Button
            Button {
                withAnimation(.easeOut(duration: 0.1)) {
                    engine.decrementIncline()
                }
            } label: {
                Text("−")
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassPanel(cornerRadius: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Color.white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
            .buttonStyle(HitButtonStyle())
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.3))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 1),
            alignment: .leading
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

#Preview("Workout Dashboard") {
    let engine = PatternEngine()
    engine.selectedPattern = .pyramid
    engine.goalDurationSeconds = 2700
    engine.start()

    return WorkoutView(
        bleManager: BluetoothManager(),
        engine: engine,
        healthManager: HealthManager(),
        onStop: { }
    )
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}

#Preview("Workout — iPad") {
    let engine = PatternEngine()
    engine.selectedPattern = .hiit
    engine.goalDurationSeconds = 1800
    engine.start()

    return WorkoutView(
        bleManager: BluetoothManager(),
        engine: engine,
        healthManager: HealthManager(),
        onStop: { }
    )
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
    .previewDevice("iPad Pro (13-inch) (M4)")
    .previewInterfaceOrientation(.landscapeLeft)
}
