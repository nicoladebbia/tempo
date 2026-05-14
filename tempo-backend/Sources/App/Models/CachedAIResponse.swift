import Fluent
import Vapor

// MARK: - CachedAIResponse
//
// Per AI_INTELLIGENCE_ENGINE.md §6 + INTELLIGENCE_REMEDIATION_PLAN.md §6.
//
// Postgres-backed cache for AI responses that need to outlive Redis (weekly
// reports, training programs, study schedules, achievement copy). One row per
// (feature, cache_key) pair. `payload` is a JSON-encoded string of the typed
// response value; AICache handles encode/decode.

final class CachedAIResponse: Model, Content, @unchecked Sendable {
    static let schema = "ai_response_cache"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "feature")
    var feature: String

    @Field(key: "cache_key")
    var cacheKey: String

    /// JSON-encoded response payload. Stored as TEXT (not JSONB) because the
    /// backend never queries inside it — only round-trips the whole blob.
    @Field(key: "payload")
    var payload: String

    @Field(key: "generated_at")
    var generatedAt: Date

    /// Soft TTL. Past this timestamp the entry is "stale" but still readable.
    /// AICache returns stale values to callers and triggers async refresh
    /// (stale-while-revalidate, spec §6.2).
    @Field(key: "expires_at")
    var expiresAt: Date

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        feature: String,
        cacheKey: String,
        payload: String,
        generatedAt: Date,
        expiresAt: Date
    ) {
        self.feature = feature
        self.cacheKey = cacheKey
        self.payload = payload
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
    }
}
