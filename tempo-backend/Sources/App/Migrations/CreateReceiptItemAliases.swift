import Fluent

// MARK: - Create Receipt Item Aliases Migration

// Crowd-sourced receipt-line -> expanded-item mapping. When many different
// users scan a receipt with the same raw OCR text at the same store chain
// and agree on the same expansion, `is_trusted` flips true and the app can
// look the mapping up instantly instead of re-guessing every time.
//
// Deliberately stores NO per-user data — no user id, no email, nothing
// identifying. `confirmation_count` is enough to build trust without
// attributing any single confirmation to a person.

struct CreateReceiptItemAliases: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("receipt_item_aliases")
            .id()
            .field("store_chain", .string, .required)
            .field("normalized_raw_text", .string, .required)
            .field("expanded_name", .string, .required)
            .field("canonical_food_name", .string, .required)
            .field("barcode", .string)
            .field("confirmation_count", .int, .required, .sql(.default(1)))
            .field("is_trusted", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .unique(on: "store_chain", "normalized_raw_text")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("receipt_item_aliases").delete()
    }
}
