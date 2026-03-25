import Fluent

// MARK: - Create Whoop Workouts Migration
// Per BACKEND_API.md — whoop_workouts table.

struct CreateWhoopWorkouts: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("whoop_workouts")
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("whoop_workout_id", .int64, .required)
            .field("date", .date, .required)
            .field("sport_id", .int, .required)
            .field("sport_name", .string, .required)
            .field("start_time", .datetime, .required)
            .field("end_time", .datetime, .required)
            .field("strain", .double)
            .field("average_heart_rate", .int)
            .field("max_heart_rate", .int)
            .field("kilojoule", .double)
            .field("percent_recorded", .double)
            .field("distance_meter", .double)
            .field("altitude_gain_meter", .double)
            .field("altitude_change_meter", .double)
            .field("zone_zero_milli", .int64)
            .field("zone_one_milli", .int64)
            .field("zone_two_milli", .int64)
            .field("zone_three_milli", .int64)
            .field("zone_four_milli", .int64)
            .field("zone_five_milli", .int64)
            .field("synced_at", .datetime, .required)
            .field("deleted_at", .datetime)
            .unique(on: "whoop_workout_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("whoop_workouts").delete()
    }
}
