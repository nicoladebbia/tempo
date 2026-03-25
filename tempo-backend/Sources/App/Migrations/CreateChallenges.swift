import Fluent
import SQLKit

// MARK: - Create Challenges + Challenge Members Migrations
// Per MODULE_ARENA.md Section 9 — Challenge system.

struct CreateChallenges: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Challenges
        try await database.schema("challenges")
            .id()
            .field("creator_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("title", .string, .required)
            .field("description", .string, .required, .sql(.default("")))
            .field("type", .string, .required) // head_to_head, group, daily
            .field("metric", .string, .required)
            .field("start_date", .date, .required)
            .field("end_date", .date, .required)
            .field("max_participants", .int, .required, .sql(.default(10)))
            .field("visibility", .string, .required, .sql(.default("friends_only")))
            .field("status", .string, .required, .sql(.default("upcoming")))
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .create()

        // Challenge Members
        try await database.schema("challenge_members")
            .id()
            .field("challenge_id", .uuid, .required, .references("challenges", "id", onDelete: .cascade))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("status", .string, .required, .sql(.default("joined")))
            .field("final_score", .double)
            .field("rank", .int)
            .field("joined_at", .datetime, .required)
            .field("completed_at", .datetime)
            .unique(on: "challenge_id", "user_id")
            .create()

        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            CREATE INDEX idx_challenges_status ON challenges(status, start_date)
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_challenge_members_user ON challenge_members(user_id, status)
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("challenge_members").delete()
        try await database.schema("challenges").delete()
    }
}
