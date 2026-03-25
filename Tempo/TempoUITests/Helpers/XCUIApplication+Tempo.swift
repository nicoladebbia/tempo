import XCTest

// MARK: - XCUIApplication Extension
// Per TESTING_STRATEGY.md Section 5 — Convenience helpers for UI tests.

extension XCUIApplication {

    /// Launch with onboarding skipped and mock data injected.
    func launchForTesting(skipOnboarding: Bool = true) {
        launchArguments = [
            TestLaunchArguments.useMockData,
            TestLaunchArguments.resetDefaults,
        ]
        if skipOnboarding {
            launchArguments.append(TestLaunchArguments.skipOnboarding)
        }
        launch()
    }

    /// Launch showing onboarding (fresh install state).
    func launchFreshInstall() {
        launchArguments = [
            TestLaunchArguments.useMockData,
            TestLaunchArguments.resetDefaults,
        ]
        launch()
    }
}
