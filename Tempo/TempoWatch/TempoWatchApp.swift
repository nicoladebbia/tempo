import SwiftUI

// MARK: - Tempo Watch App
// Per APPLE_WATCH_APP.md Section 1 — Companion Watch app entry point.
// Per XCODE_PROJECT_STRUCTURE.md Section 11.4

@main
struct TempoWatchApp: App {
    @State private var connectivityService = WatchConnectivityService.shared

    var body: some Scene {
        WindowGroup {
            GlanceHomeView(connectivity: connectivityService)
        }
    }
}
