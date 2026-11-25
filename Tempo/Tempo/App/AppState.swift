//
// AppState.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - AppTab

/// The four tabs of the shell. (Named `AppTab` so it never collides with SwiftUI's `Tab`.)
/// Recovery and Lockdown are not tabs: they open on the Today stack (`TodayRoute`).
enum AppTab: String, CaseIterable {
    case today
    case train
    case fuel
    case arena

    var title: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .today: "sun.horizon.fill"
        case .train: "dumbbell.fill"
        case .fuel: "fork.knife"
        case .arena: "trophy.fill"
        }
    }
}

// MARK: - TodayRoute

/// A full page that opens on top of Today.
enum TodayRoute: Hashable, CaseIterable {
    case recovery
    case lockdown
    /// Sleep, HRV and strain in detail.
    case body
    /// Steps, sessions and training history.
    case move
    /// Study time and exams.
    case mind
    /// Today's nutrition in detail.
    case fuel
    /// The whole day as a timeline.
    case day
    /// The week just gone, in four lines.
    case weekReview
}

// MARK: - MealRequest

/// A meal a notification wants on screen.
struct MealRequest: Equatable, Identifiable {
    enum Action: Equatable {
        /// Show the meal.
        case open
        /// Show the meal with Mark eaten already open.
        case markEaten
    }

    let id: UUID
    let action: Action
}

/// A session Siri, Shortcuts, the Action button or a widget wants started the
/// moment the app is up. `TempoSystemRequestHost` acts on it and clears it.
enum StartRequest: Equatable {
    /// Start (or pick up) today's session.
    case workout
    /// Start a focus timer; nil minutes = the app's usual length.
    case focus(minutes: Int?)
}
// MARK: - CoachRequest

/// A Recovery Coach session a notification wants on screen (WHOOP v2 workout id).
struct CoachRequest: Equatable, Identifiable {
    let id: String
}

// MARK: - NutritionRoute

/// A Nutrition section (and Kitchen sub-section) a notification wants shown.
struct NutritionRoute: Equatable {
    var section: NutritionSection
    var kitchen: KitchenSection?
}

// MARK: - TrainRoute

/// A page inside Train that search wants open. The Train tab applies and clears it.
struct TrainRoute: Equatable {
    var page: TrainDestination
    /// The exercise to find when the page is the Exercise Library.
    var exercise: String?
}

// MARK: - SettingsRequest

/// Settings, optionally open on one page. The shell presents it as a sheet.
struct SettingsRequest: Equatable, Identifiable {
    let id = UUID()
    let page: SettingsDestination?
}

// MARK: - AppState

@Observable
@MainActor
final class AppState {
    var isOnboardingComplete: Bool {
        didSet { UserDefaults.standard.set(isOnboardingComplete, forKey: "tempo.onboarding.complete") }
    }

    var activeTab: AppTab = .today
    /// Pages pushed on the Today stack (Recovery, Lockdown).
    var todayPath: [TodayRoute] = []
    /// Today's 0-100 day score, published by the Today screen. Drives the app's mood colours.
    var dayScore: Int?
    /// Set to show the "+" capture sheet.
    var captureRequested = false
    /// Set by the Sunday notification's "Something's different" — ContentView
    /// opens the weekly check-in.
    var weeklyCheckInRequested = false
    /// Set by a meal notification (tap, "Log meal", "View meal"):
    /// ContentView presents that meal.
    var requestedMeal: MealRequest?
    /// Set by the "Session done. Weigh in now." push tap: ContentView presents the Recovery Coach.
    var requestedCoach: CoachRequest?
    /// Set by a notification that wants a specific Nutrition section (Plan for
    /// "week is ready", Kitchen › Supplements …); ContentView applies and clears it.
    var requestedNutrition: NutritionRoute?
    /// Set by the "Start workout" / "Start focus" intents and `tempo://start/...` links.
    var requestedStart: StartRequest?
    /// Set to show the search sheet.
    var searchRequested = false
    /// Set by search: a Train page to open. The Train tab applies and clears it.
    var requestedTrain: TrainRoute?
    /// Set to present Settings (or one page of it) from anywhere. The shell presents it.
    var requestedSettings: SettingsRequest?
    /// Set to present the "Ask Tempo" chat from anywhere. The shell presents it.
    var askRequested = false
    var isOffline: Bool = false

    private let authService: AuthService

    /// Switches to Today and shows `route` on top of it.
    func openOnToday(_ route: TodayRoute) {
        open(.today, todayRoute: route)
    }

    /// Goes to `tab`. Today ends up showing exactly `todayRoute` (or its own
    /// page when nil): a page left open from earlier never stays on top of
    /// where a notification or shortcut meant to land.
    func open(_ tab: AppTab, todayRoute: TodayRoute? = nil) {
        activeTab = tab
        let path = todayRoute.map { [$0] } ?? []
        if todayPath != path {
            todayPath = path
        }
    }

    /// Pushes `route` on Today, unless it is already the page on top (a
    /// double tap must not open the same page twice).
    @discardableResult
    func pushOnToday(_ route: TodayRoute) -> Bool {
        guard todayPath.last != route else {
            return false
        }
        todayPath.append(route)
        return true
    }

    var authState: AuthState {
        authService.authState
    }

    init(authService: AuthService) {
        self.authService = authService

        // UI test launch arguments
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitesting-reset") {
            UserDefaults.standard.removeObject(forKey: "tempo.onboarding.complete")
            UserDefaults.standard.removeObject(forKey: "dashboard.signInNudgeDismissedAt")
            TodayCache.shared.clear()
        }
        if args.contains("--uitesting-skip-onboarding") {
            isOnboardingComplete = true
        } else {
            isOnboardingComplete = UserDefaults.standard.bool(forKey: "tempo.onboarding.complete")
        }
    }
}
