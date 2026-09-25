//
// SettingsSignInFlowTests.swift
// Tempo
//
//

import XCTest

// MARK: - Settings Sign-In Flow Tests

// A user who finished onboarding without signing in can still sign in from
// Settings → Account (otherwise every AI call fails as "session expired").

final class SettingsSignInFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testSignedOutUserCanSignInFromAccountSettings() {
        app.launchForTesting()
        app.tabBars.buttons["Nutrition"].tap()
        app.buttons["Settings"].firstMatch.tap()

        let account = app.staticTexts["Not signed in — tap to sign in"]
        for _ in 0 ..< 8 where !account.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()

        XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "account-signed-out"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Signed out → the Dashboard shows the sign-in nudge with Apple's button;
    /// "Not now" hides it.
    func testDashboardShowsSignInNudgeWhenSignedOut() {
        app.launchArguments = [
            TestLaunchArguments.useMockData, TestLaunchArguments.resetDefaults,
            TestLaunchArguments.skipOnboarding, "--uitesting-signin-nudge",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Sign in to unlock your AI coach"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Sign in with Apple"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "dashboard-signin-nudge"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["Not now"].tap()
        XCTAssertFalse(app.staticTexts["Sign in to unlock your AI coach"].waitForExistence(timeout: 2))
    }
}
