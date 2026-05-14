import Fluent

// MARK: - Add ai_consent_at to users
// Per AI_INTELLIGENCE_ENGINE.md §11.3 + INTELLIGENCE_REMEDIATION_PLAN.md §4.6.
// Records when the user explicitly consented to AI processing of health data.
// Nullable — absence of value means no consent (SubscriptionMiddleware returns
// 402 with ai_consent_required for any AI route).

struct AddAIConsentToUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("ai_consent_at", .datetime)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("ai_consent_at")
            .update()
    }
}
