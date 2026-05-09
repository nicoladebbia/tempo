//
// OnboardingPage.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import XCTest

// MARK: - Onboarding Page Object

// Per TESTING_STRATEGY.md — Page object for onboarding flow.

final class OnboardingPage: BasePage {
    // MARK: - Elements

    var splashView: XCUIElement {
        app.staticTexts["TEMPO"]
    }

    var continueButton: XCUIElement {
        app.buttons["Continue"]
    }

    var skipButton: XCUIElement {
        app.buttons["Skip"]
    }

    var backButton: XCUIElement {
        app.buttons["Back"]
    }

    var getStartedButton: XCUIElement {
        app.buttons["LET'S GO"]
    }

    var signInButton: XCUIElement {
        app.buttons["Sign in with Apple"]
    }

    /// Setup fields
    var displayNameField: XCUIElement {
        app.textFields.firstMatch
    }

    /// Completion
    var completionTitle: XCUIElement {
        app.staticTexts["YOU'RE IN."]
    }

    // MARK: - Actions

    func waitForSplash() {
        waitForElement(splashView)
    }

    func tapContinue() {
        if continueButton.waitForExistence(timeout: 3) {
            continueButton.tap()
        }
    }

    func tapSkip() {
        if skipButton.waitForExistence(timeout: 3) {
            skipButton.tap()
        }
    }

    func tapBack() {
        backButton.tap()
    }

    func tapGetStarted() {
        if getStartedButton.waitForExistence(timeout: 3) {
            getStartedButton.tap()
        }
    }

    // MARK: - Verifications

    var isOnSplash: Bool {
        splashView.exists
    }

    var isOnCompletion: Bool {
        completionTitle.waitForExistence(timeout: 5)
    }
}
