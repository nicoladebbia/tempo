import Fluent

// MARK: - Add Supplement Catalog Reports Migration

// App Store 1.2 safeguards for the shared catalog. Additive only, so it is safe on a
// populated database: new defaulted columns (report_count, dispute_count on entries,
// agrees on confirmations; existing rows read as 0 / 0 / true) plus a new reports table.

struct AddSupplementCatalogReports: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("supplement_catalog_entries")
            .field("report_count", .int, .required, .sql(.default(0)))
            .field("dispute_count", .int, .required, .sql(.default(0)))
            .update()

        try await database.schema("supplement_catalog_confirmations")
            .field("agrees", .bool, .required, .sql(.default(true)))
            .update()

        try await database.schema("supplement_catalog_reports")
            .id()
            .field("entry_id", .uuid, .required, .references("supplement_catalog_entries", "id", onDelete: .cascade))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("created_at", .datetime, .required)
            .unique(on: "entry_id", "user_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("supplement_catalog_reports").delete()
        try await database.schema("supplement_catalog_confirmations").deleteField("agrees").update()
        try await database.schema("supplement_catalog_entries")
            .deleteField("report_count").deleteField("dispute_count").update()
    }
}
