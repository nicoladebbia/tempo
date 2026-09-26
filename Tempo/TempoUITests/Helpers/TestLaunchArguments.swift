//
// TestLaunchArguments.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - Test Launch Arguments

// Per TESTING_STRATEGY.md Section 5 — Launch arguments to inject mock data.

enum TestLaunchArguments {
    /// Skip onboarding — goes straight to main tab view.
    static let skipOnboarding = "--uitesting-skip-onboarding"

    /// Use mock data for all services.
    static let useMockData = "--uitesting-mock-data"

    /// Reset all user defaults on launch.
    static let resetDefaults = "--uitesting-reset"

    /// Start from an empty in-memory SwiftData store (no profile, no plans).
    static let emptyStore = "--uitesting-empty-store"

    /// Start on a specific tab.
    static func startTab(_ tab: String) -> String {
        "--uitesting-start-tab=\(tab)"
    }
}
