import SwiftUI

// MARK: - Tempo Watch App
// Per APPLE_WATCH_APP.md Section 3.1 — NavigationStack with vertically-paging TabView.
// 5 pages: Glance, Workout, Focus Timer, Quick Log, Recovery.

@main
struct TempoWatchApp: App {
    @State private var connectivityService = WatchConnectivityService.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                GlanceHomeView(connectivity: connectivityService)
                WorkoutView(connectivity: connectivityService)
                FocusTimerView(connectivity: connectivityService)
                QuickLogView(connectivity: connectivityService)
                RecoveryView(connectivity: connectivityService)
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
