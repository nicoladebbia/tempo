import Fluent

struct CreateUserDailyPlanProfiles: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("user_daily_plan_profiles")
            .id()
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .unique(on: "user_id")
            .field("wake_time_minutes", .int, .required)
            .field("sleep_target_hours", .double, .required)
            .field("chronotype", .string, .required)
            .field("training_time_preference", .string, .required)
            .field("eating_window_preset", .string, .required)
            .field("eating_window_start_minutes", .int, .required)
            .field("eating_window_end_minutes", .int, .required)
            .field("breakfast_skipped", .bool, .required)
            .field("post_workout_mandatory", .bool, .required)
            .field("study_session_length_minutes", .int, .required)
            .field("weekend_differential", .string, .required)
            .field("term_start_date", .datetime)
            .field("term_end_date", .datetime)
            .field("class_blocks_json", .string, .required)
            .field("work_blocks_json", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("user_daily_plan_profiles").delete()
    }
}
