import Fluent
import Vapor

// MARK: - User Model
// Per VAPOR_PROJECT_STRUCTURE.md Section 5 — User model with soft delete.
// Per BACKEND_API.md Section 21 — users table schema.

final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "apple_user_id")
    var appleUserID: String

    @Field(key: "username")
    var username: String

    @Field(key: "display_name")
    var displayName: String

    @OptionalField(key: "bio")
    var bio: String?

    @OptionalField(key: "avatar_url")
    var avatarURL: String?

    @Field(key: "timezone")
    var timezone: String

    @Field(key: "xp_total")
    var xpTotal: Int

    @Field(key: "level")
    var level: Int

    @Field(key: "streak_days")
    var streakDays: Int

    @OptionalField(key: "streak_last_date")
    var streakLastDate: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @OptionalField(key: "deleted_at")
    var deletedAt: Date?

    @OptionalField(key: "suspended_at")
    var suspendedAt: Date?

    @OptionalField(key: "last_active_at")
    var lastActiveAt: Date?

    /// Set when the user explicitly consents to having their health data sent
    /// to Anthropic for AI-powered insights. Null = no consent (AI features
    /// return 402). Per AI_INTELLIGENCE_ENGINE.md §11.3 +
    /// INTELLIGENCE_REMEDIATION_PLAN.md §4.6.
    @OptionalField(key: "ai_consent_at")
    var aiConsentAt: Date?

    /// When the user explicitly accepted the Terms of Service + Privacy
    /// Policy. Required by Apple Guideline 5.1.1 and GDPR; the
    /// ToSGateMiddleware refuses non-auth, non-tos requests with 451 when
    /// this is null. Per LAUNCH_PUNCH_LIST.md §3.5.
    @OptionalField(key: "tos_accepted_at")
    var tosAcceptedAt: Date?

    // ── Relationships ──────────────────────────
    @Children(for: \.$user)
    var refreshTokens: [RefreshToken]

    // ── Initializers ───────────────────────────
    init() {}

    init(
        appleUserID: String,
        username: String,
        displayName: String = "",
        timezone: String = "UTC"
    ) {
        self.id = "usr_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24).description
        self.appleUserID = appleUserID
        self.username = username
        self.displayName = displayName
        self.timezone = timezone
        self.xpTotal = 0
        self.level = 1
        self.streakDays = 0
    }

    // ── Computed ───────────────────────────────

    /// Check if account is soft-deleted.
    var isDeleted: Bool { deletedAt != nil }

    /// Check if in 30-day recovery window.
    var isRecoverable: Bool {
        guard let deletedAt else { return false }
        return Date().timeIntervalSince(deletedAt) < 30 * 24 * 3600
    }

    /// Compute level from XP total.
    static func levelForXP(_ xp: Int) -> Int {
        let thresholds = [
            0, 100, 500, 1_000, 2_500, 5_000,
            7_500, 10_000, 15_000, 25_000, 50_000, 100_000
        ]
        var level = 1
        for (i, threshold) in thresholds.enumerated() {
            if xp >= threshold { level = i + 1 }
        }
        return level
    }
}
