import XCTest

// MARK: - Dashboard Page Object
// Per TESTING_STRATEGY.md — Page object for main dashboard.

final class DashboardPage: BasePage {

    // MARK: - Elements

    var tabBar: XCUIElement { app.tabBars.firstMatch }
    var dashboardTab: XCUIElement { app.tabBars.buttons["Dashboard"] }
    var trainingTab: XCUIElement { app.tabBars.buttons["Training"] }
    var lockdownTab: XCUIElement { app.tabBars.buttons["Lockdown"] }
    var recoveryTab: XCUIElement { app.tabBars.buttons["Recovery"] }
    var arenaTab: XCUIElement { app.tabBars.buttons["Arena"] }

    // Dashboard content
    var scoreRing: XCUIElement { app.otherElements["scoreRing"].firstMatch }

    // MARK: - Actions

    func navigateToTraining() {
        trainingTab.tap()
    }

    func navigateToLockdown() {
        lockdownTab.tap()
    }

    func navigateToRecovery() {
        recoveryTab.tap()
    }

    func navigateToArena() {
        arenaTab.tap()
    }

    func navigateToDashboard() {
        dashboardTab.tap()
    }

    // MARK: - Verifications

    var isTabBarVisible: Bool {
        tabBar.waitForExistence(timeout: 10)
    }

    var isDashboardSelected: Bool {
        dashboardTab.isSelected
    }
}
