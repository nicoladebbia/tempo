import XCTest

// MARK: - Dashboard Flow Tests
// Per BUILD_PLAN Step 19.4, TESTING_STRATEGY.md Section 5.
// Tests dashboard navigation and basic interactions.

final class DashboardFlowTests: XCTestCase {

    private var app: XCUIApplication!
    private var dashboard: DashboardPage!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        dashboard = DashboardPage(app: app)
    }

    func testDashboardLoads() {
        app.launchForTesting()
        XCTAssertTrue(dashboard.isTabBarVisible, "Dashboard should load with tab bar")
    }

    func testNavigateToTrainingAndBack() {
        app.launchForTesting()
        XCTAssertTrue(dashboard.isTabBarVisible)
        dashboard.navigateToTraining()
        dashboard.navigateToDashboard()
        XCTAssertTrue(dashboard.isDashboardSelected)
    }

    func testNavigateToLockdown() {
        app.launchForTesting()
        dashboard.navigateToLockdown()
        // Verify we're on lockdown tab
        XCTAssertTrue(app.tabBars.buttons["Lockdown"].isSelected)
    }

    func testNavigateToRecovery() {
        app.launchForTesting()
        dashboard.navigateToRecovery()
        XCTAssertTrue(app.tabBars.buttons["Recovery"].isSelected)
    }

    func testNavigateToArena() {
        app.launchForTesting()
        dashboard.navigateToArena()
        XCTAssertTrue(app.tabBars.buttons["Arena"].isSelected)
    }

    func testTabBarPersistsAcrossNavigation() {
        app.launchForTesting()
        // Navigate through all tabs and verify tab bar stays
        for tab in ["Training", "Lockdown", "Recovery", "Arena", "Dashboard"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(dashboard.isTabBarVisible,
                          "Tab bar should remain visible on \(tab) tab")
        }
    }
}
