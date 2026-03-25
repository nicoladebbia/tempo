import Fluent
import SQLKit

// MARK: - Create Achievement Definitions + User Achievements Migrations
// Per MODULE_ARENA.md Section 21 — Achievement system.

struct CreateAchievements: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Achievement Definitions (seeded data)
        try await database.schema("achievement_definitions")
            .field("id", .string, .identifier(auto: false))
            .field("name", .string, .required)
            .field("description", .string, .required)
            .field("category", .string, .required) // training, study, nutrition, recovery, streaks, social, steps
            .field("tier", .string, .required) // common, rare, epic, legendary, mythic
            .field("xp_reward", .int, .required)
            .field("criteria_type", .string, .required)
            .field("criteria_threshold", .int, .required)
            .field("icon_name", .string)
            .field("hidden", .bool, .required, .sql(.default(false)))
            .field("flavor_text", .string)
            .field("created_at", .datetime, .required)
            .create()

        // User Achievements (earned)
        try await database.schema("user_achievements")
            .id()
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("achievement_id", .string, .required, .references("achievement_definitions", "id", onDelete: .cascade))
            .field("earned_at", .datetime, .required)
            .field("pinned", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime, .required)
            .unique(on: "user_id", "achievement_id")
            .create()

        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            CREATE INDEX idx_user_achievements_user ON user_achievements(user_id, earned_at DESC)
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_achievements").delete()
        try await database.schema("achievement_definitions").delete()
    }
}
