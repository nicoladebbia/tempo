import Fluent

// MARK: - Create Brand Catalog Items Migration

// Optional backend-backed brand/size catalog for the iOS
// `ReceiptProductMatcher` (which also carries a bundled JSON fallback for
// when this is unreachable). Rows are seeded/refreshed from Open Food Facts'
// `brands_tags` search — see BrandCatalogRefreshing for the (currently
// no-op) refresh seam.
//
// `barcode` is "unique-ish" per product-requirements wording, not enforced
// as a hard unique constraint here: OFF data can have duplicate/missing
// barcodes across pack sizes, and de-duping isn't needed for this table to
// be useful as a lookup/typeahead source.

struct CreateBrandCatalogItems: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("brand_catalog_items")
            .id()
            .field("brand", .string, .required)
            .field("chain", .string)
            .field("name", .string, .required)
            .field("generic_name", .string)
            .field("size_value", .double)
            .field("size_unit", .string)
            .field("pack_count", .int)
            .field("barcode", .string)
            .field("image_url", .string)
            // XPEvent.metadata ([String: String]?, see CreateXPEvents) is a
            // JSON column — but FluentPostgresDriver encodes a bare `[String]`
            // Swift array as a native Postgres ARRAY (text[]), not JSON, so
            // `categories` needs an array column type to match what's
            // actually sent on the wire (a `.json` column here 500s every
            // insert with "column categories is of type jsonb but expression
            // is of type text[]").
            .field("categories", .array(of: .string))
            .field("updated_at", .datetime, .required)
            .field("is_stale", .bool, .required, .sql(.default(false)))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("brand_catalog_items").delete()
    }
}
