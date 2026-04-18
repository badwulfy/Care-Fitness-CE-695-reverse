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
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// Dummy trigger : quand il change, SwiftUI re-évalue body et relit liveWindowInsets.
    @State private var orientationTrigger: Int = 0

    /// Lit les insets UIKit de façon synchrone à chaque render de body.
    /// Contrairement à @State, ceci est toujours à jour au moment du rendu.
    private var liveWindowInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    var onStop: () -> Void

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Vrai landscape = iPhone en mode paysage OU iPad (toujours large)
    private var isLandscape: Bool {
        guard !isPad else { return true }
        return hSizeClass == .regular
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
        // liveWindowInsets est relu à chaque fois que body s'évalue.
        // orientationTrigger force ce re-rendu après chaque rotation.
        let _ = orientationTrigger
        let win = liveWindowInsets

        GeometryReader { geo in
            let isActuallyLandscape = geo.size.width > geo.size.height || isPad
            let insets = geo.safeAreaInsets

            Group {
                if isActuallyLandscape {
                    landscapeLayout(geoInsets: insets, windowInsets: win)
                } else {
                    portraitLayout(insets: insets)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isActuallyLandscape)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Délai pour laisser UIKit finaliser la rotation, puis force un re-render.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { orientationTrigger += 1 }
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

    // MARK: - Layouts

    /// Layout landscape (iPhone + iPad)
    /// - geoInsets : insets du GeometryReader (fiables pour top/bottom)
    /// - windowInsets : insets de la UIWindow (fiables pour leading/trailing / DI)
    @ViewBuilder
    private func landscapeLayout(geoInsets: EdgeInsets, windowInsets: UIEdgeInsets) -> some View {
        // On utilise windowInsets pour détecter la position réelle de la Dynamic Island.
        let diOnLeft = windowInsets.left > windowInsets.right
        let leadingSafe = CGFloat(windowInsets.left)
        let trailingSafe = CGFloat(windowInsets.right)

        HStack(spacing: 0) {
            VStack(spacing: isPad ? 20 : 0) {
                chartPanel
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, isPad ? 0 : 16)

                if isPad { metricsGrid(isCompact: false).padding(.bottom, 8) }

                footerControls
                    .frame(height: isPad ? 64 : 56)
            }
            // Si DI à gauche → on décale le contenu pour ne pas être sous l'encoche.
            .padding(.leading, diOnLeft ? max(leadingSafe, 16) : 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)

            if !isPad {
                metricsGrid(isCompact: true)
                    .padding(.vertical, 12)
                    .frame(width: 280)
            }

            // Si DI à droite → on donne de l'espace trailing au panel résistance.
            let rightSafeArea = diOnLeft ? 0 : trailingSafe
            resistancePanel(trailingSafeArea: rightSafeArea)
                .frame(width: isPad ? 160 : 130 + rightSafeArea)
        }
        .ignoresSafeArea(.all, edges: [.horizontal, .bottom])
    }

    /// Layout portrait de secours (iPhone pas encore tourné / rotation ratée)
    @ViewBuilder
    private func portraitLayout(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            chartPanel
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            metricsGrid(isCompact: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            HStack(spacing: 12) {
                footerControls
                    .frame(maxWidth: .infinity)

                resistancePanel(trailingSafeArea: 0)
                    .frame(width: 110)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, max(insets.bottom, 8))
        }
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

    private func metricsGrid(isCompact: Bool) -> some View {
        let tel = ble.telemetry

        if !isCompact {
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
                        MetricCard(title: "Vitesse", value: String(format: "%.1f", tel.speedKmh), unit: "km/h", color: .neonGreen, isLarge: false)
                        MetricCard(title: "Puiss.", value: "\(tel.watts)", unit: "W", color: .neonYellow, isLarge: false)
                    }
                    .frame(height: 85)

                    HStack(spacing: hSpacing) {
                        MetricCard(title: "Pulse \(hrSource)", value: displayedHR > 0 ? "\(displayedHR)" : "--", unit: "bpm", color: .neonRed, icon: "heart.fill", isLarge: false)
                        MetricCard(title: "Chrono", value: engine.formattedElapsed, unit: "", color: .white, isLarge: false)
                    }
                    .frame(height: 85)
                    .frame(maxHeight: .infinity)

                    HStack(spacing: hSpacing) {
                        MetricCard(title: "Cadence", value: "\(tel.rpm)", unit: "RPM", color: .neonCyan, isLarge: false)
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

    private func resistancePanel(trailingSafeArea: CGFloat) -> some View {
        ResistancePanel(isPad: isPad, safeAreaTrailing: trailingSafeArea)
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
