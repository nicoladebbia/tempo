import Fluent

// MARK: - Create Receipts Migration

// Top-level receipt record. Owns its line items via cascade-delete on the
// receipt_line_items.receipt_id FK.

struct CreateReceipts: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("receipts")
            .field("id", .string, .identifier(auto: false))
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("store", .string, .required)
            .field("store_location", .string)
            .field("purchase_date", .datetime, .required)
            .field("total_amount", .double, .required)
            .field("tax_amount", .double)
            .field("payment_method", .string)
            .field("photo_path", .string)
            .field("ocr_status", .string, .required)
            .field("ocr_raw_text", .string)
            .field("ocr_provider", .string, .required)
            .field("user_reviewed", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("receipts").delete()
    }
}
