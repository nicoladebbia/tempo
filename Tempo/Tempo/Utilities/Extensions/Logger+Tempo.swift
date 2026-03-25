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

    /// NutriTrack integration, meal logging.
    static let nutritrack = Logger(subsystem: subsystem, category: "nutritrack")

    /// Calendar/EventKit integration.
    static let calendar = Logger(subsystem: subsystem, category: "calendar")

    /// Notifications, scheduling, escalation.
    static let notifications = Logger(subsystem: subsystem, category: "notifications")

    /// Authentication, keychain, Sign in with Apple.
    static let auth = Logger(subsystem: subsystem, category: "auth")
}
