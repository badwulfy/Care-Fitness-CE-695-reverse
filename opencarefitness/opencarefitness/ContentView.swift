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

// MARK: - Layout Constants

private enum FloatingUI {
    static let topInset: CGFloat   = 60
    static let bottomInset: CGFloat = 76
}

// MARK: - Content View

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    // Remote Managers
    @Environment(NavigationManager.self) private var nav
    @Environment(BluetoothManager.self) private var ble
    @Environment(PatternEngine.self) private var engine
    @Environment(HealthManager.self) private var health
    @Environment(WorkoutSessionManager.self) private var sessionManager
    
    @Namespace private var tabNamespace

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

            mainContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    if nav.currentScreen != .workout {
                        Color.clear.frame(height: FloatingUI.topInset)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if nav.currentScreen != .workout {
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

            if nav.currentScreen != .workout {
                floatingOverlay
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: .init(get: { !nav.hasCompletedOnboarding }, set: { _ in })) {
            // Placeholder for OnboardingView
            VStack {
                Text("Bienvenue sur OpenCare Fitness")
                    .font(.title)
                Button("Commencer") {
                    nav.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: .init(
            get: { nav.isShowingSettings },
            set: { nav.isShowingSettings = $0 }
        )) {
            // Placeholder for SettingsView
            Text("Paramètres")
        }
        .task {
            await health.requestAuthorization()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        // Telemetry Monitoring (moved the storage to sessionManager)
        .onChange(of: ble.telemetry.lastUpdate) { _, _ in
            guard nav.currentScreen == .workout else { return }
            sessionManager.updateStats(
                hr: ble.telemetry.heartRate,
                watts: ble.telemetry.watts,
                rpm: ble.telemetry.rpm,
                incline: engine.currentIncline
            )
        }
        .onChange(of: ble.telemetry.rpm) { _, rpm in
            // Auto-start from Setup
            if nav.currentScreen == .setup && rpm > 10 && ble.connectionState == .connected {
                startWorkout()
            }
        }
        .onChange(of: ble.telemetry.distance) { _, distance in
            guard nav.currentScreen == .workout else { return }
            engine.currentDistanceHm = distance
        }
        .onChange(of: engine.isGoalReached) { _, reached in
            if reached && nav.currentScreen == .workout {
                stopWorkout()
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch nav.currentScreen {
        case .setup:
            SetupView(onStart: startWorkout)
        case .workout:
            WorkoutView(onStop: stopWorkout)
        case .summary:
            if let session = sessionManager.lastSession {
                SummaryView(
                    session: session,
                    onDismiss: { nav.navigate(to: .setup) }
                )
            }
        case .history:
            HistoryView()
        }
    }

    // MARK: - Floating Overlay

    @ViewBuilder
    private var floatingOverlay: some View {
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
            BLEStatusBadge(state: ble.connectionState)
                .frame(maxWidth: .infinity, alignment: .leading)

            if ble.connectionState == .disconnected || ble.connectionState == .error {
                Button {
                    ble.startScanning()
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
            
            // Settings Button
            Button {
                nav.isShowingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .padding(.horizontal, 20)
    }

    // MARK: - Bottom Tab Bar

    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            TabButton(title: "Préparation", icon: "play.fill", isActive: nav.currentScreen == .setup, namespace: tabNamespace) {
                nav.navigate(to: .setup)
            }
            TabButton(title: "Historique", icon: "calendar", isActive: nav.currentScreen == .history, namespace: tabNamespace) {
                nav.navigate(to: .history)
            }
        }
        .padding(6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
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
        sessionManager.start()
        
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone, let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        #endif

        nav.navigate(to: .workout)
    }

    private func stopWorkout() {
        _ = sessionManager.stop(context: modelContext)
        
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone, let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
        #endif

        nav.navigate(to: .summary)
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard nav.currentScreen == .workout else { return }
        switch phase {
        case .background, .inactive:
            ble.targetResistance = 1
            if engine.isRunning && !engine.isPaused { engine.pause() }
        case .active:
            ble.targetResistance = engine.currentResistance
        @unknown default: break
        }
    }
}

// MARK: - BLE Status Badge

private struct BLEStatusBadge: View {
    let state: BLEConnectionState
    private var dotColor: Color {
        switch state {
        case .connected: return .green
        case .scanning, .connecting, .initializing: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if state == .connected {
                    Circle().fill(dotColor.opacity(0.35)).frame(width: 14, height: 14)
                }
                Circle().fill(dotColor).frame(width: 7, height: 7)
            }
            Text(state.rawValue).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Device Battery

private struct DeviceBatteryView: View {
    @State private var level: Int = -1
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: batteryIcon).font(.system(size: 11))
            Text(level >= 0 ? "\(level)%" : "--%").font(.system(size: 11, design: .monospaced))
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
        default: return "battery.25"
        }
    }
    #if os(iOS)
    private func updateBattery() {
        let raw = UIDevice.current.batteryLevel
        level = raw >= 0 ? Int(raw * 100) : -1
    }
    #endif
}
