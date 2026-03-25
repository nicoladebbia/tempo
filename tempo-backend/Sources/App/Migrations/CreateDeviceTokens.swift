import Fluent

// MARK: - Create Device Tokens Migration
// Per BUILD_PLAN step 12.1 — APNs device token storage.

struct CreateDeviceTokens: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("device_tokens")
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("token", .string, .required)
            .field("device_id", .string, .required)
            .field("device_name", .string)
            .field("platform", .string, .required)
            .field("app_version", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id", "device_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("device_tokens").delete()
    }
}
