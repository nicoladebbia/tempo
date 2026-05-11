import Fluent

// MARK: - Drop NutriTrack Integrations Migration

// NutriTrack proxy was removed in favor of native nutrition. This migration drops the
// table created by CreateNutriTrackIntegrations. The original migration file is kept
// (never amend committed migrations) but is now a no-op in effect because this
// migration runs after it and removes the table.
//
// Revert reinstates an empty placeholder table so downgrade paths don't crash on
// references; in practice no consumer code points at this table anymore.

struct DropNutriTrackIntegrations: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("nutritrack_integrations").delete()
    }

    func revert(on database: Database) async throws {
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
}
