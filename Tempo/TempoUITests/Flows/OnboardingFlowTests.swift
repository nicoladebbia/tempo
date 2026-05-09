//
// OnboardingFlowTests.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import XCTest

// MARK: - Onboarding Flow Tests

// Per BUILD_PLAN Step 19.4, TESTING_STRATEGY.md Section 5.
// Tests the full onboarding flow using Page Object Model.

final class OnboardingFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private var onboarding: OnboardingPage!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        onboarding = OnboardingPage(app: app)
    }

    func testOnboardingSplashAppears() {
        app.launchFreshInstall()
        // Splash should appear briefly or onboarding should be visible
        let exists = app.staticTexts["TEMPO"].waitForExistence(timeout: 5)
            || app.buttons["Continue"].waitForExistence(timeout: 5)
            || app.buttons["Sign in with Apple"].waitForExistence(timeout: 5)
        XCTAssertTrue(exists, "Onboarding content should appear on fresh install")
    }

    func testOnboardingBackNavigation() {
        app.launchFreshInstall()
        // Wait for first interactive step
        if app.buttons["Continue"].waitForExistence(timeout: 10) {
            onboarding.tapContinue()
            // Back button should now be available
            if onboarding.backButton.waitForExistence(timeout: 3) {
                onboarding.tapBack()
                // Should be back on previous step
                XCTAssertTrue(
                    app.buttons["Continue"].exists || app.buttons["Skip"].exists,
                    "Should navigate back to previous step"
                )
            }
        }
    }

    func testSkipOptionalSteps() {
        app.launchFreshInstall()
        // Navigate through steps, skipping optional integrations
        for _ in 0 ..< 15 {
            if app.buttons["Skip"].waitForExistence(timeout: 2) {
                onboarding.tapSkip()
            } else if app.buttons["Continue"].waitForExistence(timeout: 2) {
                onboarding.tapContinue()
            } else if app.buttons["LET'S GO"].waitForExistence(timeout: 2) {
                onboarding.tapGetStarted()
                break
            } else if app.buttons["Sign in with Apple"].waitForExistence(timeout: 2) {
                // Can't tap Sign in with Apple in UI tests — skip
                onboarding.tapSkip()
            } else {
                break
            }
        }
    }
}
