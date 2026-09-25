//
// XCUIApplication+Tempo.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import XCTest

// MARK: - XCUIApplication Extension

// Per TESTING_STRATEGY.md Section 5 — Convenience helpers for UI tests.

extension XCUIApplication {
    /// Launch with onboarding skipped and mock data injected. `extraArguments`
    /// appends feature-specific fixtures (e.g. guided run mode's
    /// GuidedRunUITestSeed launch argument) without every flow needing its
    /// own launch helper.
    func launchForTesting(skipOnboarding: Bool = true, extraArguments: [String] = []) {
        launchArguments = [
            TestLaunchArguments.useMockData,
            TestLaunchArguments.resetDefaults,
        ]
        if skipOnboarding {
            launchArguments.append(TestLaunchArguments.skipOnboarding)
        }
        launchArguments.append(contentsOf: extraArguments)
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
