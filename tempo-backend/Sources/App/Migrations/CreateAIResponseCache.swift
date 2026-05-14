import Fluent
import SQLKit

// MARK: - Create AI Response Cache Migration
//
// Per AI_INTELLIGENCE_ENGINE.md §6 + INTELLIGENCE_REMEDIATION_PLAN.md §6.
//
// Postgres-backed cache for long-lived AI responses (weekly reports, training
// programs, study schedules, achievement copy). Redis handles short-TTL hot
// caches separately.

struct CreateAIResponseCache: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("ai_response_cache")
            .id()
            .field("feature", .string, .required)
            .field("cache_key", .string, .required)
            .field("payload", .string, .required)
            .field("generated_at", .datetime, .required)
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .unique(on: "cache_key")
            .create()

        guard let sql = database as? SQLDatabase else { return }

        // AICache lookup hot path:
        //   SELECT payload FROM ai_response_cache WHERE cache_key = $1
        // The unique constraint above already covers this. We add a plain
        // composite index for cache-warming sweeps. Postgres won't accept
        // a `WHERE expires_at > NOW()` partial index because NOW() is volatile
        // (sqlState 42P17). The expires_at index below handles the same query
        // path with a range scan.
        try await sql.raw("""
            CREATE INDEX idx_ai_cache_feature_expires
            ON ai_response_cache(feature, expires_at)
            """).run()

        // For background cleanup of long-expired rows (a separate cron, not
        // SWR — SWR only handles "stale but still readable").
        try await sql.raw("""
            CREATE INDEX idx_ai_cache_expires_at
            ON ai_response_cache(expires_at)
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("ai_response_cache").delete()
    }
}
