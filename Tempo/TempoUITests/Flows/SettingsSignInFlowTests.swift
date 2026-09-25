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
}
