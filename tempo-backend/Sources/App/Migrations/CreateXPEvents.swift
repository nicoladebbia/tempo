import Fluent
import SQLKit

// MARK: - Create XP Events Migration
// Per MODULE_ARENA.md Section 2.1 — XP event tracking.

struct CreateXPEvents: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("xp_events")
            .id()
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("source", .string, .required)
            .field("base_xp", .int, .required)
            .field("multiplied_xp", .int, .required)
            .field("streak_multiplier", .double, .required, .sql(.default(1.0)))
            .field("metadata", .json)
            .field("flagged", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime, .required)
            .create()

        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            CREATE INDEX idx_xp_events_user_date ON xp_events(user_id, created_at DESC)
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_xp_events_source ON xp_events(source)
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("xp_events").delete()
    }
}
