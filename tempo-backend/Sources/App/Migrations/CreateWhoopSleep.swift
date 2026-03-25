import Fluent

// MARK: - Create Whoop Sleep Migration
// Per BACKEND_API.md — whoop_sleep table.

struct CreateWhoopSleep: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("whoop_sleep")
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("whoop_sleep_id", .int64, .required)
            .field("date", .date, .required)
            .field("start_time", .datetime, .required)
            .field("end_time", .datetime, .required)
            .field("total_in_bed_milli", .int64)
            .field("total_awake_milli", .int64)
            .field("total_light_sleep_milli", .int64)
            .field("total_slow_wave_sleep_milli", .int64)
            .field("total_rem_sleep_milli", .int64)
            .field("sleep_cycle_count", .int)
            .field("disturbance_count", .int)
            .field("baseline_sleep_need_milli", .int64)
            .field("need_from_sleep_debt_milli", .int64)
            .field("need_from_strain_milli", .int64)
            .field("need_from_nap_milli", .int64)
            .field("respiratory_rate", .double)
            .field("sleep_performance_percentage", .double)
            .field("sleep_consistency_percentage", .double)
            .field("sleep_efficiency_percentage", .double)
            .field("is_nap", .bool, .required, .sql(.default(false)))
            .field("synced_at", .datetime, .required)
            .field("deleted_at", .datetime)
            .unique(on: "whoop_sleep_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("whoop_sleep").delete()
    }
}
