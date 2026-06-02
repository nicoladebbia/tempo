//
// PantryPriceEntry.swift
// Tempo
//
// One immutable record per purchase event of a food — the price-history time
// series for "what did eggs cost over time / am I saving money". Keyed by
// `canonicalFoodName` (the STABLE food identity), NOT by PantryItem: pantry
// rows are ephemeral (consumed, decremented to zero, archived, re-bought as a
// new row), so hanging history off a PantryItem relationship would fracture a
// food's timeline into disconnected stubs every restock. Same denormalization
// pattern as MealFeedback's recipeID — provenance UUIDs are optional back-links
// only, never cascade relationships.
//
// Written by BOTH ingest paths: receipt-scan (prices already extracted into
// ReceiptLineItem) and manual add. One INSERT per purchase — restocks never
// overwrite, so the history the user asked for is preserved.
//

import Foundation
import SwiftData

@Model
final class PantryPriceEntry {
    @Attribute(.unique)
    var id: UUID

    /// Stable food identity — the query key for a food's price time series.
    /// Denormalized plain String (indexed) so the record survives PantryItem
    /// archival/deletion. Output of FoodCanonicalizer, lowercased on write.
    var canonicalFoodName: String

    /// Human-facing label as captured at purchase (e.g. "Large eggs, dozen").
    var displayName: String

    /// When this price was locked in — the purchase date (receipt date when
    /// scanned, else now on manual add). This is the x-axis of the trend.
    var purchaseDate: Date

    /// Total USD paid for this purchase line (the figure the user chose to
    /// track). Per-unit comparison is derived from quantity/unit below.
    var totalPaidUSD: Double

    /// Quantity + unit purchased, kept so "savings over time" can compare
    /// per-unit cost ($3.20 for 6 eggs vs $3.60 for 12 is otherwise
    /// meaningless). `unit` stored raw to match PantryItem's pattern.
    var quantity: Double
    var unitRaw: String

    /// Optional normalized cost per kg from the receipt OCR (nil for manual
    /// entries or non-mass units). Convenience for cross-food comparison.
    var pricePerKg: Double?

    /// Where this price came from. Raw string of PantryPurchaseSource.
    var sourceRaw: String

    /// Store name when known (receipt scan supplies it; manual is nil).
    var store: String?

    /// Provenance back-links — optional UUIDs, NOT relationships, so they
    /// can't cascade-delete this history when the source row goes away.
    var sourcePantryItemID: UUID?
    var sourceReceiptLineItemID: UUID?

    var createdAt: Date

    // MARK: - Transient

    @Transient
    var unit: PantryUnit {
        PantryUnit(rawValue: unitRaw) ?? .pieces
    }

    @Transient
    var source: PantryPurchaseSource {
        PantryPurchaseSource(rawValue: sourceRaw) ?? .manual
    }

    /// Per-unit USD cost (total ÷ quantity), the comparable figure for trends.
    /// nil when quantity is non-positive (avoids divide-by-zero garbage).
    @Transient
    var pricePerUnitUSD: Double? {
        guard quantity > 0 else { return nil }
        return totalPaidUSD / quantity
    }

    init(
        id: UUID = UUID(),
        canonicalFoodName: String,
        displayName: String,
        purchaseDate: Date,
        totalPaidUSD: Double,
        quantity: Double,
        unit: PantryUnit,
        pricePerKg: Double? = nil,
        source: PantryPurchaseSource = .manual,
        store: String? = nil,
        sourcePantryItemID: UUID? = nil,
        sourceReceiptLineItemID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.canonicalFoodName = canonicalFoodName.lowercased()
        self.displayName = displayName
        self.purchaseDate = purchaseDate
        self.totalPaidUSD = totalPaidUSD
        self.quantity = quantity
        unitRaw = unit.rawValue
        self.pricePerKg = pricePerKg
        sourceRaw = source.rawValue
        self.store = store
        self.sourcePantryItemID = sourcePantryItemID
        self.sourceReceiptLineItemID = sourceReceiptLineItemID
        self.createdAt = createdAt
    }
}
