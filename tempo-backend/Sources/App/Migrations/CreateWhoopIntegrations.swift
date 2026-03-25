import Fluent

// MARK: - Create Whoop Integrations Migration
// Per INTEGRATION_SPECS.md Section 1 — Stores encrypted Whoop OAuth tokens.

struct CreateWhoopIntegrations: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("whoop_integrations")
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("encrypted_access_token", .string, .required)
            .field("encrypted_refresh_token", .string, .required)
            .field("token_expires_at", .datetime, .required)
            .field("whoop_user_id", .string)
            .field("scopes", .string)
            .field("connected_at", .datetime, .required)
            .field("last_sync_at", .datetime)
            .field("last_sync_status", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("whoop_integrations").delete()
    }
}
