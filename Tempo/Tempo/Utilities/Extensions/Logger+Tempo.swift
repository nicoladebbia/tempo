//
// Logger+Tempo.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.tempo"

    /// Network requests, API calls, response handling.
    static let networking = Logger(subsystem: subsystem, category: "networking")

    /// HealthKit reads, writes, background delivery.
    static let healthkit = Logger(subsystem: subsystem, category: "healthkit")

    /// Whoop API integration, OAuth, webhooks.
    static let whoop = Logger(subsystem: subsystem, category: "whoop")

    /// Training engine, workout generation, progressive overload.
    static let training = Logger(subsystem: subsystem, category: "training")

    /// Recovery engine, sleep analysis, strain.
    static let recovery = Logger(subsystem: subsystem, category: "recovery")

    /// Sync coordinator, background sync, conflict resolution.
    static let sync = Logger(subsystem: subsystem, category: "sync")

    /// StoreKit subscriptions, entitlement checks.
    static let subscription = Logger(subsystem: subsystem, category: "subscription")

    /// Calendar/EventKit integration.
    static let calendar = Logger(subsystem: subsystem, category: "calendar")

    /// Notifications, scheduling, escalation.
    static let notifications = Logger(subsystem: subsystem, category: "notifications")

    /// Authentication, keychain, Sign in with Apple.
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// PostHog analytics, event tracking, feature flags.
    static let analytics = Logger(subsystem: subsystem, category: "analytics")

    /// Nutrition services: food search, meal logging, photo analysis.
    ///
    /// DIAGNOSTICS: filterable one-line summaries for on-device debugging are
    /// tagged `[Diag.<area>]` so the Xcode console can be filtered to just our
    /// lines (type "Diag" in the console filter to hide Whoop/keyboard/system
    /// noise). Current areas:
    ///   [Diag.Plan]    — plan generation: input training schedule, per-day
    ///                    times + day-types, variety audit, supplement decisions
    ///   [Diag.Eat]     — a meal marked eaten (name, time, kcal, pantry flag)
    ///   [Diag.Undo]    — a meal reverted to planned (from eaten OR skipped)
    ///   [Diag.Grocery] — grocery list generated (item count) or failed
    static let nutrition = Logger(subsystem: subsystem, category: "nutrition")
}
