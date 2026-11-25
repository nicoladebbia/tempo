import Fluent

// MARK: - Create Friend Invites
// Additive: a new table for the shareable "add me" links.

struct CreateFriendInvites: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("friend_invites")
            .id()
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("token", .string, .required)
            .field("created_at", .datetime)
            .field("revoked_at", .datetime)
            .unique(on: "token")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("friend_invites").delete()
    }
}
