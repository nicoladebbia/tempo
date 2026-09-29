//
// ReceiptItemAlias.swift
// Tempo
//
// Layer-2 of the receipt item resolver: a locally-learned correction. When a
// user fixes a line item's readable name in the review UI once, we remember
// it forever for that (store chain, normalized raw text) pair so the same
// abbreviated OCR string resolves instantly next time — no dictionary pass,
// no AI call. See ReceiptItemResolver.swift for the read/write logic that
// owns this model; this file only defines storage.
//

import Foundation
import SwiftData

// MARK: - ReceiptItemAlias

@Model
final class ReceiptItemAlias {
    @Attribute(.unique)
    var id: UUID

    /// Lowercased store chain key ("publix", "walmart", ...), matching
    /// ReceiptStoreBrandPrefixes.json's "chain" field. Falls back to
    /// "unknown" when the receipt didn't identify a chain.
    var storeChain: String

    /// Normalized (lowercased, whitespace-collapsed, punctuation-stripped)
    /// raw OCR text — see ReceiptItemResolver.normalize(_:). This is the
    /// lookup key alongside storeChain.
    var normalizedRawText: String

    /// User-confirmed, human-facing name ("Publix Greek Yogurt 0% Fat").
    var readableName: String

    /// User-confirmed (or re-derived) canonical food name for pantry matching.
    var canonicalFoodName: String

    /// Optional barcode captured when the user matched this line to a
    /// scanned/looked-up product.
    var barcode: String?

    /// Number of times this exact correction has been confirmed. Starts at
    /// 1 on first learn; bumped on every repeat confirmation so the review
    /// UI can show "seen 4 times" confidence.
    var confirmCount: Int

    var createdAt: Date

    var updatedAt: Date

    init(
        id: UUID = UUID(),
        storeChain: String,
        normalizedRawText: String,
        readableName: String,
        canonicalFoodName: String,
        barcode: String? = nil,
        confirmCount: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.storeChain = storeChain
        self.normalizedRawText = normalizedRawText
        self.readableName = readableName
        self.canonicalFoodName = canonicalFoodName
        self.barcode = barcode
        self.confirmCount = max(1, confirmCount)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - DTO

extension ReceiptItemAlias {
    struct DTO: Codable, Sendable {
        let id: UUID
        let store_chain: String
        let normalized_raw_text: String
        let readable_name: String
        let canonical_food_name: String
        let barcode: String?
        let confirm_count: Int
        let created_at: Date
        let updated_at: Date
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            store_chain: storeChain,
            normalized_raw_text: normalizedRawText,
            readable_name: readableName,
            canonical_food_name: canonicalFoodName,
            barcode: barcode,
            confirm_count: confirmCount,
            created_at: createdAt,
            updated_at: updatedAt
        )
    }
}
