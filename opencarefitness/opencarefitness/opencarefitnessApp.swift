//
//  opencarefitnessApp.swift
//  opencarefitness
//
//  Created by Alexandre Derniame on 17/04/2026.
//

import SwiftUI
import SwiftData

@main
struct opencarefitnessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State private var navigationManager = NavigationManager()
    @State private var bleManager = BluetoothManager()
    @State private var engine = PatternEngine()
    @State private var healthManager = HealthManager()
    @State private var sessionManager: WorkoutSessionManager

    init() {
        let ble = BluetoothManager()
        let eng = PatternEngine()
        let health = HealthManager()
        
        self._bleManager = State(initialValue: ble)
        self._engine = State(initialValue: eng)
        self._healthManager = State(initialValue: health)
        self._sessionManager = State(initialValue: WorkoutSessionManager(bleManager: ble, engine: eng, healthManager: health))
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WorkoutSession.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(navigationManager)
                .environment(bleManager)
                .environment(engine)
                .environment(healthManager)
                .environment(sessionManager)
        }
        .modelContainer(sharedModelContainer)
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.allButUpsideDown

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}
