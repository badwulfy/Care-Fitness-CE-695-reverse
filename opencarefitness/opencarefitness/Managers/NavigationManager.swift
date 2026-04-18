//
//  NavigationManager.swift
//  opencarefitness
//
//  Centralized navigation and app state.
//

import SwiftUI

enum AppScreen: Equatable {
    case setup
    case workout
    case summary
    case history
}

@Observable
final class NavigationManager {
    // Current screen in the main app flow
    var currentScreen: AppScreen = .setup
    
    // Onboarding management
    @ObservationIgnored
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    // Control for sheets/modals
    var isShowingSettings: Bool = false
    
    func navigate(to screen: AppScreen) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentScreen = screen
        }
    }
    
    func completeOnboarding() {
        withAnimation {
            hasCompletedOnboarding = true
        }
    }
}
