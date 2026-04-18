//
//  ContentView.swift
//  opencarefitness
//
//  Root view: navigation between Setup → Workout → Summary screens.
//  Manages lifecycle, BLE connection, and background safety.
//
//  Layout strategy:
//  • The main content fills the real safe-area, not the whole screen.
//  • safeAreaInset(edge:) reserves space for the floating pill (top) and
//    the floating tab bar (bottom) so every ScrollView automatically clears
//    them on any device — no device-specific magic numbers needed.
//  • A separate ZStack layer renders the actual floating glass elements.
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

// MARK: - Layout Constants

private enum FloatingUI {
    /// Space reserved above content for the status pill + gap.
    /// The VStack that shows the pill respects the safe area, so this inset is
    /// added *on top of* the existing safe-area-top.
    static let topInset: CGFloat   = 60
    /// Space reserved below content for the tab bar capsule + gap.
    static let bottomInset: CGFloat = 76
}

// MARK: - Content View

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var screen: AppScreen = .setup
    @State private var bleManager = BluetoothManager()
    @State private var engine = PatternEngine()
    @State private var healthManager = HealthManager()
    @Namespace private var tabNamespace

    // Workout stats accumulation
    @State private var hrSamples: [Int] = []
    @State private var wattsSamples: [Int] = []
    @State private var rpmSamples: [Int] = []
    @State private var maxWatts: Int = 0
    @State private var maxHR: Int = 0
    @State private var maxIncline: Double = 0

    @State private var lastSession: WorkoutSession?

    private var isPad: Bool {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return true
        #endif
    }

    var body: some View {
        ZStack(alignment: .top) {
            // ── Background ─────────────────────────────────────────────────
            Color.appBackground.ignoresSafeArea()

            // ── Main Content ───────────────────────────────────────────────
            // Content fills the normal safe area (no ignoresSafeArea hack).
            // safeAreaInset() extends the safe area so ScrollViews inside
            // automatically add inset for the floating pill and tab bar.
            mainContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    if screen != .workout {
                        Color.clear.frame(height: FloatingUI.topInset)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if screen != .workout {
                        Color.clear.frame(height: FloatingUI.bottomInset)
                    }
                }
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.05),
                            .init(color: .black, location: 0.95),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            // ── Floating Glass Layer ───────────────────────────────────────
            if screen != .workout {
                floatingOverlay
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await healthManager.requestAuthorization()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
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

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch screen {
        case .setup:
            SetupView(engine: engine, bleManager: bleManager, onStart: startWorkout)
        case .workout:
            WorkoutView(bleManager: bleManager, engine: engine, healthManager: healthManager, onStop: stopWorkout)
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

    // MARK: - Floating Overlay

    /// All floating glass elements rendered above the content layer.
    /// They live in their own ZStack children so they never interfere with
    /// content layout.
    @ViewBuilder
    private var floatingOverlay: some View {
        // ── Floating Elements ────────────────────────
        // This VStack respects the safe area, so padding values are
        // relative to the safe area edge — device-independent.
        VStack(spacing: 0) {
            statusPill
                .padding(.top, 10)
                .frame(maxHeight: .infinity, alignment: .top)

            bottomTabBar
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
    }

    // MARK: - Status Pill

    private var statusPill: some View {
        HStack(spacing: 10) {
            BLEStatusBadge(state: bleManager.connectionState)
                .frame(maxWidth: .infinity, alignment: .leading)

            if bleManager.connectionState == .disconnected || bleManager.connectionState == .error {
                Button {
                    bleManager.startScanning()
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.neonCyan)
                }
                .buttonStyle(.plain)
            }

            DeviceBatteryView()

            Text(Date.now, format: .dateTime.hour().minute())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .padding(.horizontal, 20)
    }

    // MARK: - Bottom Tab Bar

    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            TabButton(
                title: "Préparation",
                icon: "play.fill",
                isActive: screen == .setup,
                namespace: tabNamespace
            ) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    screen = .setup
                }
            }

            TabButton(
                title: "Historique",
                icon: "calendar",
                isActive: screen == .history,
                namespace: tabNamespace
            ) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    screen = .history
                }
            }
        }
        .padding(6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }

    // MARK: - Tab Button

    private struct TabButton: View {
        let title: String
        let icon: String
        let isActive: Bool
        let namespace: Namespace.ID
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(isActive ? .black : .white.opacity(0.6))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background {
                    if isActive {
                        Capsule()
                            .fill(.white)
                            .matchedGeometryEffect(id: "activeTab", in: namespace)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Workout Lifecycle

    private func startWorkout() {
        hrSamples = []
        wattsSamples = []
        rpmSamples = []
        maxWatts = 0
        maxHR = 0
        maxIncline = 0

        bleManager.targetResistance = engine.currentResistance
        engine.start()

        Task { await healthManager.startWorkout() }

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone,
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        #endif

        withAnimation(.easeInOut(duration: 0.3)) { screen = .workout }
    }

    private func stopWorkout() {
        engine.stop()
        bleManager.targetResistance = 1

        Task { await healthManager.endWorkout() }

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone,
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
        #endif

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

        modelContext.insert(session)
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

        withAnimation(.easeInOut(duration: 0.3)) { screen = .summary }
    }

    // MARK: - Background Safety

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard screen == .workout else { return }
        switch phase {
        case .background, .inactive:
            bleManager.targetResistance = 1
            if engine.isRunning && !engine.isPaused { engine.pause() }
        case .active:
            bleManager.targetResistance = engine.currentResistance
        @unknown default:
            break
        }
    }
}

// MARK: - BLE Status Badge

private struct BLEStatusBadge: View {
    let state: BLEConnectionState

    private var dotColor: Color {
        switch state {
        case .connected:                                        return .green
        case .scanning, .connecting, .initializing:            return .yellow
        case .disconnected:                                     return .gray
        case .error:                                            return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if state == .connected {
                    Circle()
                        .fill(dotColor.opacity(0.35))
                        .frame(width: 14, height: 14)
                }
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
            }

            Text(state.rawValue)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Device Battery

private struct DeviceBatteryView: View {
    @State private var level: Int = -1

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: batteryIcon)
                .font(.system(size: 11))
            Text(level >= 0 ? "\(level)%" : "--%")
                .font(.system(size: 11, design: .monospaced))
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

    private var batteryIcon: String {
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
        level = raw >= 0 ? Int(raw * 100) : -1
    }
    #endif
}

// MARK: - Previews

#Preview("App — iPhone") {
    ContentView()
        .modelContainer(for: WorkoutSession.self, inMemory: true)
}

#Preview("App — iPad Landscape", traits: .landscapeLeft) {
    ContentView()
        .modelContainer(for: WorkoutSession.self, inMemory: true)
}
