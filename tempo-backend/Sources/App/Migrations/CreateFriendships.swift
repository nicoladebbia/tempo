import Fluent
import SQLKit

// MARK: - Create Friendships + Friend Requests Migrations
// Per MODULE_ARENA.md Section 9 — Friend system.

struct CreateFriendships: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Friendships (accepted pairs)
        try await database.schema("friendships")
            .id()
            .field("user_a_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("user_b_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("created_at", .datetime, .required)
            .unique(on: "user_a_id", "user_b_id")
            .create()

        // Friend Requests
        try await database.schema("friend_requests")
            .id()
            .field("from_user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("to_user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("status", .string, .required, .sql(.default("pending")))
            .field("created_at", .datetime, .required)
            .field("responded_at", .datetime)
            .unique(on: "from_user_id", "to_user_id")
            .create()

        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            CREATE INDEX idx_friendships_user_a ON friendships(user_a_id)
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_friendships_user_b ON friendships(user_b_id)
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_friend_requests_to ON friend_requests(to_user_id, status)
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("friend_requests").delete()
        try await database.schema("friendships").delete()
    }
}
