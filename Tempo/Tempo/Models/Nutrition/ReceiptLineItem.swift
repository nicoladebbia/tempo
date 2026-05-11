//
// ReceiptLineItem.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - ReceiptLineUnit

// Receipt prints almost always use lb/oz/each; gram/kilogram are rare on US
// receipts but supported for parity with PantryUnit.

enum ReceiptLineUnit: String, Codable, CaseIterable, Sendable {
    case pounds = "lb"
    case ounces = "oz"
    case kilograms = "kg"
    case grams = "g"
    case each
    case unit

    /// Map to a PantryUnit for ingest. Pounds + ounces convert later via
    /// quantityGrams, but the chosen pantry unit follows the receipt verbatim
    /// — a `lb` receipt line creates a `pounds` pantry entry.
    var asPantryUnit: PantryUnit {
        switch self {
        case .pounds: .pounds
        case .ounces: .ounces
        case .kilograms: .kilograms
        case .grams: .grams
        case .each,
             .unit: .pieces
        }
    }
}

// MARK: - ReceiptLineItem

@Model
final class ReceiptLineItem {
    @Attribute(.unique)
    var id: UUID

    /// Parent receipt (nullify on delete — cascade owns lifecycle from Receipt side).
    @Relationship(deleteRule: .nullify)
    var receipt: Receipt?

    // MARK: - Raw text + canonical

    /// Exactly as printed: "GV CHKN BRST 1.32LB", "BANANAS 0.69 LB".
    var rawText: String

    /// Output of FoodCanonicalizer.canonicalize.
    var canonicalFoodName: String

    /// Output of FoodCanonicalizer.displayName.
    var displayName: String

    // MARK: - Quantity + price

    var quantity: Double

    var unitRaw: String

    /// Normalized grams when known — used for $/kg trend analytics.
    var quantityGrams: Double?

    var unitPrice: Double?

    var totalPrice: Double

    var pricePerKg: Double?

    // MARK: - Sale info

    var onSale: Bool

    /// "BOGO", "2 for $5", etc. Free-text.
    var saleNote: String?

    // MARK: - Confidence + review

    /// OCR / Haiku confidence in this line. 0.0–1.0.
    var confidence: Double

    /// Becomes `true` when the user approves this line in the review UI.
    var userConfirmed: Bool

    /// Pantry item ID created from this line on confirm. Lets us undo the
    /// ingestion (and prevent double-ingest if the user confirms twice).
    var linkedPantryItemID: UUID?

    var createdAt: Date

    // MARK: - Computed

    @Transient
    var unit: ReceiptLineUnit {
        get { ReceiptLineUnit(rawValue: unitRaw) ?? .unit }
        set { unitRaw = newValue.rawValue }
    }

    @Transient
    var isIngested: Bool {
        linkedPantryItemID != nil
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        receipt: Receipt? = nil,
        rawText: String,
        canonicalFoodName: String,
        displayName: String,
        quantity: Double,
        unit: ReceiptLineUnit,
        quantityGrams: Double? = nil,
        unitPrice: Double? = nil,
        totalPrice: Double,
        pricePerKg: Double? = nil,
        onSale: Bool = false,
        saleNote: String? = nil,
        confidence: Double = 1.0,
        userConfirmed: Bool = false,
        linkedPantryItemID: UUID? = nil
    ) {
        self.id = id
        self.receipt = receipt
        self.rawText = rawText
        self.canonicalFoodName = canonicalFoodName
        self.displayName = displayName
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.quantityGrams = quantityGrams
        self.unitPrice = unitPrice
        self.totalPrice = totalPrice
        self.pricePerKg = pricePerKg
        self.onSale = onSale
        self.saleNote = saleNote
        self.confidence = max(0, min(1, confidence))
        self.userConfirmed = userConfirmed
        self.linkedPantryItemID = linkedPantryItemID
        self.createdAt = Date()
    }
}

// MARK: - DTO

extension ReceiptLineItem {
    struct DTO: Codable, Sendable {
        let id: UUID
        let raw_text: String
        let canonical_food_name: String
        let display_name: String
        let quantity: Double
        let unit: String
        let quantity_grams: Double?
        let unit_price: Double?
        let total_price: Double
        let price_per_kg: Double?
        let on_sale: Bool
        let sale_note: String?
        let confidence: Double
        let user_confirmed: Bool
        let linked_pantry_item_id: UUID?
        let created_at: Date
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            raw_text: rawText,
            canonical_food_name: canonicalFoodName,
            display_name: displayName,
            quantity: quantity,
            unit: unitRaw,
            quantity_grams: quantityGrams,
            unit_price: unitPrice,
            total_price: totalPrice,
            price_per_kg: pricePerKg,
            on_sale: onSale,
            sale_note: saleNote,
            confidence: confidence,
            user_confirmed: userConfirmed,
            linked_pantry_item_id: linkedPantryItemID,
            created_at: createdAt
        )
    }
}
