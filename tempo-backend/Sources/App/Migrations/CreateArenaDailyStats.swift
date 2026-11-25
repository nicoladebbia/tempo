import Fluent

// MARK: - Create Arena Daily Stats
// Additive: a new table. Weekly XP (friends leaderboard) and challenge
// standings are sums over these rows.

struct CreateArenaDailyStats: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("arena_daily_stats")
            .id()
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("day", .string, .required)
            .field("xp", .int, .required, .sql(.default(0)))
            .field("workouts", .int, .required, .sql(.default(0)))
            .field("study_minutes", .int, .required, .sql(.default(0)))
            .field("updated_at", .datetime)
            .unique(on: "user_id", "day")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("arena_daily_stats").delete()
    }
}
