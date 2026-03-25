import XCTest

// MARK: - Base Page Object
// Per TESTING_STRATEGY.md Section 5 — Page Object Model for UI tests.

class BasePage {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Wait for an element to exist, with timeout.
    @discardableResult
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// Tap a tab bar button by its label.
    func tapTab(_ label: String) {
        app.tabBars.buttons[label].tap()
    }
}
