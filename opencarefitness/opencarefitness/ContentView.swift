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

    @State private var setupActivitySeconds = 0
    @State private var autoStartCooldownUntil = Date.distantPast

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
            .onAppear { recoverCrashedSessionIfNeeded() }
            .onChange(of: scenePhase, handleScenePhaseChange)
            .onChange(of: ble.telemetry.lastUpdate, updateStats)
            .onChange(of: ble.telemetry.distance, updateDistance)
            .onChange(of: engine.isGoalReached, checkGoalReached)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                evaluateSetupAutoStart()
            }
    }

    private func recoverCrashedSessionIfNeeded() {
        if let recovered = sessionManager.recoverInFlightSessionIfNeeded(context: modelContext) {
            print("[Recovery] Restored crashed session of \(recovered.durationSeconds)s")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var mainTabView: some View {
        ZStack(alignment: .bottom) {
            TabView {
                Tab {
                    SetupView(onStart: { startWorkout() })
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

            // Liquid Glass ambient haze just above the tab bar
            tabBarBlurHaze
        }
    }

    @ViewBuilder
    private var tabBarBlurHaze: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: 1)
            .mask {
                LinearGradient(
                    colors: [.clear, .white],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                // Soft neon glow line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.neonCyan.opacity(0.0),
                                Color.neonCyan.opacity(0.18),
                                Color.neonPurple.opacity(0.10),
                                Color.neonCyan.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .blur(radius: 6)
            }
            .padding(.bottom, 82) // juste au-dessus de la tab bar native
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

    private func updateDistance() {
        guard nav.currentScreen == .workout else { return }
        engine.currentDistanceHm = ble.telemetry.distance
    }

    private func checkGoalReached() {
        if engine.isGoalReached && nav.currentScreen == .workout {
            stopWorkout()
        }
    }

    private func evaluateSetupAutoStart() {
        guard nav.hasCompletedOnboarding,
              nav.currentScreen == .setup,
              !engine.isRunning,
              ble.effectiveConnectionState == .connected,
              Date() >= autoStartCooldownUntil else {
            setupActivitySeconds = 0
            return
        }

        // Seuil de fraîcheur des données synchronisé sur 3.0s
        let telemetryIsFresh = Date().timeIntervalSince(ble.telemetry.lastUpdate) <= 3.0
        let sustainedActivity = ble.telemetry.rpm >= 20 || ble.telemetry.watts >= 35 || ble.telemetry.speedKmh >= 4.0

        if telemetryIsFresh && sustainedActivity {
            setupActivitySeconds += 1
            // Démarrage automatique après 3 secondes d'activité soutenue
            if setupActivitySeconds >= 3 {
                startWorkout(autoTriggered: true)
                setupActivitySeconds = 0
            }
        } else {
            setupActivitySeconds = 0
        }
    }

    // MARK: - Workout Lifecycle

    private func startWorkout(autoTriggered: Bool = false) {
        guard nav.currentScreen != .workout, !engine.isRunning else { return }
        if autoTriggered && ble.effectiveConnectionState != .connected {
            return
        }

        sessionManager.start()

        #if os(iOS)
        // Empêche l'écran de se verrouiller pendant qu'on pédale — l'utilisateur
        // a les mains sur le guidon, l'inactivité tactile est attendue.
        UIApplication.shared.isIdleTimerDisabled = true

        // Trigger the rotation, then wait for iOS to actually rotate before
        // presenting WorkoutView. Otherwise the fullScreenCover slides up in
        // portrait and rotates afterwards (jarring portrait → landscape flash).
        if UIDevice.current.userInterfaceIdiom == .phone {
            DeviceOrientationHelper.lockOrientation(.landscapeRight)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                nav.navigate(to: .workout)
            }
        } else {
            nav.navigate(to: .workout)
        }
        #else
        nav.navigate(to: .workout)
        #endif
    }

    private func stopWorkout() {
        let saved = sessionManager.stop(context: modelContext)
        autoStartCooldownUntil = Date().addingTimeInterval(8)
        setupActivitySeconds = 0
        let nextScreen: AppScreen = (saved == nil) ? .setup : .summary

        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false

        // Same idea reversed: rotate back to portrait first, then swap views.
        if UIDevice.current.userInterfaceIdiom == .phone {
            DeviceOrientationHelper.lockOrientation(.portrait)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                nav.navigate(to: nextScreen)
            }
        } else {
            nav.navigate(to: nextScreen)
        }
        #else
        nav.navigate(to: nextScreen)
        #endif
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
