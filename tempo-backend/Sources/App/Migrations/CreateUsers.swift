import Fluent
import SQLKit

// MARK: - Create Users Migration
// Per VAPOR_PROJECT_STRUCTURE.md Section 6 — CreateUsers migration.
// Per BACKEND_API.md Section 21 — users table schema.

struct CreateUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("id", .string, .identifier(auto: false))
            .field("apple_user_id", .string, .required)
            .field("username", .string, .required)
            .field("display_name", .string, .required, .sql(.default("")))
            .field("bio", .string)
            .field("avatar_url", .string)
            .field("timezone", .string, .required, .sql(.default("UTC")))
            .field("xp_total", .int, .required, .sql(.default(0)))
            .field("level", .int, .required, .sql(.default(1)))
            .field("streak_days", .int, .required, .sql(.default(0)))
            .field("streak_last_date", .date)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .field("deleted_at", .datetime)
            .field("suspended_at", .datetime)
            .field("last_active_at", .datetime)
            .unique(on: "apple_user_id")
            .unique(on: "username")
            .create()

        // Partial indexes for active users
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            CREATE INDEX idx_users_username_active ON users(username) WHERE deleted_at IS NULL
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_users_xp_total ON users(xp_total DESC)
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_users_last_active ON users(last_active_at DESC) WHERE deleted_at IS NULL
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users").delete()
    }
}
