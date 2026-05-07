//
// AppState.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - Tab

enum Tab: String, CaseIterable {
    case dashboard
    case recovery
    case training
    case nutrition
    case lockdown

    var title: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .recovery: "heart.fill"
        case .training: "dumbbell.fill"
        case .nutrition: "leaf.fill"
        case .lockdown: "lock.fill"
        }
    }
}

// MARK: - AppState

@Observable
@MainActor
final class AppState {
    var isOnboardingComplete: Bool {
        didSet { UserDefaults.standard.set(isOnboardingComplete, forKey: "tempo.onboarding.complete") }
    }

    var activeTab: Tab = .dashboard
    var isOffline: Bool = false

    private let authService: AuthService

    var authState: AuthState {
        authService.authState
    }

    init(authService: AuthService) {
        self.authService = authService

        // UI test launch arguments
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitesting-reset") {
            UserDefaults.standard.removeObject(forKey: "tempo.onboarding.complete")
        }
        if args.contains("--uitesting-skip-onboarding") {
            isOnboardingComplete = true
        } else {
            isOnboardingComplete = UserDefaults.standard.bool(forKey: "tempo.onboarding.complete")
        }
    }
}
