import Foundation

enum Tab: String, CaseIterable, Sendable {
    case dashboard
    case training
    case lockdown
    case recovery
    case arena

    var title: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .training: "dumbbell.fill"
        case .lockdown: "lock.fill"
        case .recovery: "heart.fill"
        case .arena: "trophy.fill"
        }
    }
}

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
            self.isOnboardingComplete = true
        } else {
            self.isOnboardingComplete = UserDefaults.standard.bool(forKey: "tempo.onboarding.complete")
        }
    }
}
