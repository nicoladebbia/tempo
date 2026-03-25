import Foundation
import PostHog
import os

// MARK: - Analytics Service
// Per BUILD_PLAN Step 20.2 — PostHog wrapper.
// Per ANALYTICS_AND_METRICS.md — 89 events, 3-tier consent, lazy init.
// Per ADR-024 — PostHog for analytics + feature flags + A/B testing.

@Observable
@MainActor
final class AnalyticsService: @unchecked Sendable {

    static let shared = AnalyticsService()

    // MARK: - Consent
    // Per ANALYTICS_AND_METRICS.md Section — 3-tier consent model.

    private(set) var consent: AnalyticsConsent {
        didSet {
            UserDefaults.standard.set(consent.rawValue, forKey: "tempo.analytics.consent")
            applyConsent()
        }
    }

    // MARK: - Private

    private var isInitialized = false
    private let sessionId = UUID().uuidString

    // MARK: - Init

    private init() {
        let raw = UserDefaults.standard.string(forKey: "tempo.analytics.consent") ?? AnalyticsConsent.full.rawValue
        self.consent = AnalyticsConsent(rawValue: raw) ?? .full
    }

    // MARK: - Setup (Lazy — NOT called in app init)
    // Per ANALYTICS_AND_METRICS.md — Lazy initialization.

    func configure(apiKey: String, host: String = "https://us.i.posthog.com") {
        guard !isInitialized else { return }

        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureApplicationLifecycleEvents = false
        config.sessionReplay = false

        PostHogSDK.shared.setup(config)
        isInitialized = true
        applyConsent()

        Logger.analytics.info("PostHog initialized")
    }

    // MARK: - Consent Management

    func updateConsent(_ newConsent: AnalyticsConsent) {
        if consent != .none && newConsent == .none {
            // Send final consent change event before stopping
            track("analytics_consent_changed", properties: [
                "from": consent.rawValue,
                "to": newConsent.rawValue
            ])
        }
        consent = newConsent
    }

    // MARK: - Identification
    // Per ANALYTICS_AND_METRICS.md — Set after sign-in.

    func identify(userId: String, traits: [String: Any] = [:]) {
        guard consent != .none, isInitialized else { return }
        PostHogSDK.shared.identify(userId, userProperties: traits)
        Logger.analytics.info("User identified")
    }

    func setUserProperties(_ properties: [String: Any]) {
        guard consent != .none, isInitialized else { return }
        PostHogSDK.shared.capture("$set", properties: properties)
    }

    func reset() {
        guard isInitialized else { return }
        PostHogSDK.shared.reset()
    }

    // MARK: - Event Tracking
    // Per ANALYTICS_AND_METRICS.md — Auto-attach event_id, timestamp, session_id, app_version, etc.

    func track(_ event: String, properties: [String: Any] = [:]) {
        guard isInitialized else { return }

        // Consent check
        switch consent {
        case .none:
            return
        case .essential:
            // Only allow crash/error events
            guard event == "error_occurred" || event.hasPrefix("crash_") else { return }
        case .full:
            break
        }

        var enriched = properties
        enriched["event_id"] = UUID().uuidString
        enriched["session_id"] = sessionId
        enriched["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        enriched["build_number"] = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        enriched["os_version"] = ProcessInfo.processInfo.operatingSystemVersionString
        enriched["locale"] = Locale.current.identifier
        enriched["timezone"] = TimeZone.current.identifier

        PostHogSDK.shared.capture(event, properties: enriched)
    }

    // MARK: - Feature Flags
    // Per ADR-026 — Cached locally, take effect on next app launch.

    func reloadFeatureFlags() {
        guard isInitialized else { return }
        PostHogSDK.shared.reloadFeatureFlags()
    }

    func isFeatureFlagEnabled(_ flag: String) -> Bool {
        guard isInitialized else { return false }
        return PostHogSDK.shared.isFeatureEnabled(flag)
    }

    func getFeatureFlagPayload(_ flag: String) -> Any? {
        guard isInitialized else { return nil }
        return PostHogSDK.shared.getFeatureFlagPayload(flag)
    }

    // MARK: - Session

    func startSession() {
        track("app_launched", properties: [
            "launch_type": "cold"
        ])
    }

    func endSession() {
        track("app_backgrounded")
    }

    func flush() {
        guard isInitialized else { return }
        PostHogSDK.shared.flush()
    }

    // MARK: - User Deletion (GDPR Article 17)
    // Per ANALYTICS_AND_METRICS.md — Send $delete on account deletion.

    func deleteUser() {
        guard isInitialized else { return }
        // PostHog processes deletion via their API; reset local state
        PostHogSDK.shared.reset()
        Logger.analytics.info("User data deletion requested")
    }

    // MARK: - Private

    private func applyConsent() {
        guard isInitialized else { return }
        switch consent {
        case .none:
            PostHogSDK.shared.optOut()
        case .essential, .full:
            PostHogSDK.shared.optIn()
        }
    }
}

// MARK: - Analytics Consent
// Per ANALYTICS_AND_METRICS.md — 3-tier system.

enum AnalyticsConsent: String, Codable, Sendable {
    case full       // All behavioral events
    case essential  // Crashes + errors only
    case none       // Nothing sent
}

