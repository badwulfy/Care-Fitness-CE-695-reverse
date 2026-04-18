//
//  ContentView.swift
//  opencarefitness
//
//  Root view: native iOS 26 TabView with automatic Liquid Glass tab bar.
//  Manages lifecycle, BLE connection, and background safety.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif
import SwiftData

// MARK: - Content View

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Environment(NavigationManager.self) private var nav
    @Environment(BluetoothManager.self) private var ble
    @Environment(PatternEngine.self) private var engine
    @Environment(HealthManager.self) private var health
    @Environment(WorkoutSessionManager.self) private var sessionManager

    var body: some View {
        mainTabView
            .preferredColorScheme(.dark)
            .fullScreenCover(isPresented: workoutBinding) {
                WorkoutView(onStop: stopWorkout)
            }
            .fullScreenCover(isPresented: summaryBinding) {
                summaryDestination
            }
            .fullScreenCover(isPresented: onboardingBinding) {
                OnboardingView()
            }
            .onChange(of: scenePhase, handleScenePhaseChange)
            .onChange(of: ble.telemetry.lastUpdate, updateStats)
            .onChange(of: ble.telemetry.rpm, checkAutoStart)
            .onChange(of: ble.telemetry.distance, updateDistance)
            .onChange(of: engine.isGoalReached, checkGoalReached)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var mainTabView: some View {
        TabView {
            Tab {
                SetupView(onStart: startWorkout)
            } label: {
                Label("Préparation", systemImage: "figure.elliptical")
                    .foregroundStyle(Color.neonCyan)
            }

            Tab {
                HistoryView()
            } label: {
                Label("Historique", systemImage: "calendar")
                    .foregroundStyle(Color.neonPurple)
            }

            Tab(role: .search) {
                SettingsView()
            } label: {
                Label("Réglages", systemImage: "gearshape.fill")
            }
        }
        .tint(Color.neonCyan)
    }

    @ViewBuilder
    private var summaryDestination: some View {
        if let session = sessionManager.lastSession {
            SummaryView(
                session: session,
                onDismiss: { nav.navigate(to: .setup) }
            )
        }
    }

    // MARK: - Bindings

    private var workoutBinding: Binding<Bool> {
        Binding(
            get: { nav.currentScreen == .workout },
            set: { if !$0 { nav.navigate(to: .setup) } }
        )
    }

    private var summaryBinding: Binding<Bool> {
        Binding(
            get: { nav.currentScreen == .summary },
            set: { if !$0 { nav.navigate(to: .setup) } }
        )
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !nav.hasCompletedOnboarding },
            set: { _ in }
        )
    }

    // MARK: - Handlers

    private func updateStats() {
        guard nav.currentScreen == .workout else { return }
        sessionManager.updateStats(
            hr: ble.telemetry.heartRate,
            watts: ble.telemetry.watts,
            rpm: ble.telemetry.rpm,
            incline: engine.currentIncline
        )
    }

    private func checkAutoStart() {
        if nav.currentScreen == .setup && ble.telemetry.rpm > 10 && ble.connectionState == .connected {
            startWorkout()
        }
    }

    private func updateDistance() {
        guard nav.currentScreen == .workout else { return }
        engine.currentDistanceHm = ble.telemetry.distance
    }

    private func checkGoalReached() {
        if engine.isGoalReached && nav.currentScreen == .workout {
            stopWorkout()
        }
    }

    // MARK: - Workout Lifecycle

    private func startWorkout() {
        sessionManager.start()

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone,
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        #endif

        nav.navigate(to: .workout)
    }

    private func stopWorkout() {
        _ = sessionManager.stop(context: modelContext)

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone,
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
        #endif

        nav.navigate(to: .summary)
    }

    private func handleScenePhaseChange(_ oldPhase: ScenePhase, _ newPhase: ScenePhase) {
        guard nav.currentScreen == .workout else { return }
        switch newPhase {
        case .background, .inactive:
            ble.targetResistance = 1
            if engine.isRunning && !engine.isPaused { engine.pause() }
        case .active:
            ble.targetResistance = engine.currentResistance
        @unknown default: break
        }
    }
}
