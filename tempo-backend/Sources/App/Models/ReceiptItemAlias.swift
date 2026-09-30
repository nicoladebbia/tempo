import Fluent
import Foundation
import Vapor

// MARK: - Receipt Item Alias Fluent Model

// A crowd-sourced (store_chain, normalized_raw_text) -> expansion mapping.
// See CreateReceiptItemAliases for the trust/no-personal-data rationale.

final class ReceiptItemAlias: Model, Content, @unchecked Sendable {
    static let schema = "receipt_item_aliases"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "store_chain")
    var storeChain: String

    @Field(key: "normalized_raw_text")
    var normalizedRawText: String

    @Field(key: "expanded_name")
    var expandedName: String

    @Field(key: "canonical_food_name")
    var canonicalFoodName: String

    @OptionalField(key: "barcode")
    var barcode: String?

    @Field(key: "confirmation_count")
    var confirmationCount: Int

    @Field(key: "is_trusted")
    var isTrusted: Bool

    @Field(key: "created_at")
    var createdAt: Date

    @Field(key: "updated_at")
    var updatedAt: Date

    init() {}

    init(
        id: UUID? = nil,
        storeChain: String,
        normalizedRawText: String,
        expandedName: String,
        canonicalFoodName: String,
        barcode: String? = nil,
        confirmationCount: Int = 1,
        isTrusted: Bool = false
    ) {
        self.id = id
        self.storeChain = storeChain
        self.normalizedRawText = normalizedRawText
        self.expandedName = expandedName
        self.canonicalFoodName = canonicalFoodName
        self.barcode = barcode
        self.confirmationCount = confirmationCount
        self.isTrusted = isTrusted
        let now = Date()
        createdAt = now
        updatedAt = now
    }
}

// MARK: - Normalization

/// Used both when writing a row and when looking one up — lowercased,
/// whitespace-collapsed, so "  PUB  GRK YOG 0%" and "pub grk yog 0%" hit the
/// same key.
enum ReceiptItemAliasNormalizer {
    static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
