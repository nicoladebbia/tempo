import Fluent
import SQLKit

// MARK: - CreateSharedGroceryLists

//
// Backs the "live shared grocery list" feature (feat/grocery-share-order).
// One row per share link. `token` is unique (used to look up the public
// /g/:token routes without exposing the numeric id) and (user_id,
// created_at DESC) is indexed for the owner's own list/lookup queries.

struct CreateSharedGroceryLists: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("shared_grocery_lists")
            .id()
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("token", .string, .required)
            .field("title", .string, .required)
            .field("store", .string)
            .field("items_json", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("revoked", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .unique(on: "token")
            .create()

        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
        CREATE INDEX idx_shared_grocery_lists_user ON shared_grocery_lists(user_id, created_at DESC)
        """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("shared_grocery_lists").delete()
    }
}
