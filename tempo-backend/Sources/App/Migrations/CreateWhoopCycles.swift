import Fluent

// MARK: - Create Whoop Cycles Migration
// Per BACKEND_API.md — whoop_cycles table.

struct CreateWhoopCycles: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("whoop_cycles")
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("whoop_cycle_id", .int64, .required)
            .field("date", .date, .required)
            .field("start_time", .datetime, .required)
            .field("end_time", .datetime)
            .field("strain", .double)
            .field("kilojoule", .double)
            .field("average_heart_rate", .int)
            .field("max_heart_rate", .int)
            .field("synced_at", .datetime, .required)
            .field("deleted_at", .datetime)
            .unique(on: "whoop_cycle_id")
            .unique(on: "user_id", "date")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("whoop_cycles").delete()
    }
}
