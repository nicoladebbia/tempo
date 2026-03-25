import Fluent
import SQLKit

// MARK: - Create Refresh Tokens Migration
// Per BACKEND_API.md Section 21 — refresh_tokens table schema.

struct CreateRefreshTokens: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("refresh_tokens")
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("device_id", .string, .required)
            .field("token_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("revoked_at", .datetime)
            .field("created_at", .datetime, .required)
            .create()

        // Indexes
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id)
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_refresh_tokens_token_hash ON refresh_tokens(token_hash) WHERE revoked_at IS NULL
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_refresh_tokens_device ON refresh_tokens(user_id, device_id)
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_refresh_tokens_cleanup ON refresh_tokens(expires_at) WHERE revoked_at IS NULL
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("refresh_tokens").delete()
    }
}
