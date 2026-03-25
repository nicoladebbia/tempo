import Fluent

// MARK: - Create NutriTrack Integrations Migration
// Per INTEGRATION_SPECS.md Section 3.1 — Stores encrypted NutriTrack PIN + base URL.

struct CreateNutriTrackIntegrations: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("nutritrack_integrations")
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("base_url", .string, .required)
            .field("encrypted_pin", .string, .required)
            .field("session_cookie", .string)
            .field("connected_at", .datetime, .required)
            .field("last_sync_at", .datetime)
            .field("last_sync_status", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("nutritrack_integrations").delete()
    }
}
