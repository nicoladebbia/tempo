//
// TempoUITests.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import XCTest

// MARK: - App Launch Tests

// Per BUILD_PLAN Step 19.4 — Basic app launch and tab navigation tests.

final class AppLaunchTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testAppLaunches() {
        app.launchForTesting()
        let dashboard = DashboardPage(app: app)
        XCTAssertTrue(dashboard.isTabBarVisible, "Tab bar should be visible after launch")
    }

    func testAllTabsAccessible() {
        app.launchForTesting()
        let dashboard = DashboardPage(app: app)
        XCTAssertTrue(dashboard.isTabBarVisible)

        // Navigate through all tabs
        dashboard.navigateToTraining()
        dashboard.navigateToLockdown()
        dashboard.navigateToRecovery()
        dashboard.navigateToArena()
        dashboard.navigateToDashboard()

        XCTAssertTrue(dashboard.isDashboardSelected)
    }
}
