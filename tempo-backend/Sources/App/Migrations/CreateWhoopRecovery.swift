import Fluent

// MARK: - Create Whoop Recovery Migration
// Per BACKEND_API.md — whoop_recovery table.

struct CreateWhoopRecovery: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("whoop_recovery")
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("whoop_cycle_id", .int64, .required)
            .field("date", .date, .required)
            .field("recovery_score", .int)
            .field("resting_heart_rate", .int)
            .field("hrv_rmssd_milli", .double)
            .field("spo2_percentage", .double)
            .field("skin_temp_celsius", .double)
            .field("user_calibrating", .bool, .required, .sql(.default(false)))
            .field("synced_at", .datetime, .required)
            .field("deleted_at", .datetime)
            .unique(on: "user_id", "date")
            .unique(on: "whoop_cycle_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("whoop_recovery").delete()
    }
}
