import Fluent

// MARK: - Create Supplement Catalog Migration

// Shared catalog of supplements users have scanned or typed in. Anti-poisoning
// design: an entry is owned by whoever created it (only they can edit it);
// everyone else can only ADD a confirmation, and `unique(entry_id, user_id)`
// makes confirmations count distinct users. Contributor ids stay server-side.

struct CreateSupplementCatalog: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("supplement_catalog_entries")
            .id()
            .field("entry_key", .string, .required)
            .field("upc", .string)
            .field("brand", .string)
            .field("name", .string, .required)
            .field("kind", .string, .required)
            .field("dose_per_serving", .string)
            .field("servings_per_container", .double)
            .field("protein_grams_per_serving", .double)
            .field("calories_per_serving", .double)
            .field("carbs_grams_per_serving", .double)
            .field("fat_grams_per_serving", .double)
            .field("ingredients", .array(of: .string), .required)
            .field("origin", .string, .required)
            .field("contributor_id", .string, .references("users", "id", onDelete: .setNull))
            .field("confirmation_count", .int, .required, .sql(.default(1)))
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .unique(on: "entry_key")
            .create()

        try await database.schema("supplement_catalog_confirmations")
            .id()
            .field("entry_id", .uuid, .required, .references("supplement_catalog_entries", "id", onDelete: .cascade))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("created_at", .datetime, .required)
            .unique(on: "entry_id", "user_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("supplement_catalog_confirmations").delete()
        try await database.schema("supplement_catalog_entries").delete()
    }
}
