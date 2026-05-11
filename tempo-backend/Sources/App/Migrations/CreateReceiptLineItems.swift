import Fluent

// MARK: - Create Receipt Line Items Migration

// One row per item parsed from a receipt. Cascade-deletes with its parent.
// `confidence` and `user_confirmed` gate pantry ingestion.

struct CreateReceiptLineItems: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("receipt_line_items")
            .field("id", .string, .identifier(auto: false))
            .field("receipt_id", .string, .required, .references("receipts", "id", onDelete: .cascade))
            .field("raw_text", .string, .required)
            .field("canonical_food_name", .string, .required)
            .field("display_name", .string, .required)
            .field("quantity", .double, .required)
            .field("unit", .string, .required)
            .field("quantity_grams", .double)
            .field("unit_price", .double)
            .field("total_price", .double, .required)
            .field("price_per_kg", .double)
            .field("on_sale", .bool, .required, .sql(.default(false)))
            .field("sale_note", .string)
            .field("confidence", .double, .required)
            .field("user_confirmed", .bool, .required, .sql(.default(false)))
            .field("linked_pantry_item_id", .string)
            .field("created_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("receipt_line_items").delete()
    }
}
