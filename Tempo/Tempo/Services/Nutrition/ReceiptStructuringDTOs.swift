//
// ReceiptStructuringDTOs.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation

// MARK: - ReceiptStructuringRequest

struct ReceiptStructuringRequest: Codable, Sendable {
    /// Raw text extracted by Apple Vision on-device (preferred when available).
    let rawText: String?

    /// Base64-encoded JPEG/PNG of the receipt. Sent when raw_text is missing
    /// or when vision confidence was low; backend uses pure Haiku Vision.
    let imageBase64: String?

    /// Media type of the image payload ("image/jpeg" / "image/png").
    let imageMediaType: String?

    /// Optional store hint when the user picked it from a list.
    let storeHint: String?

    /// Normalized chain slug when known ("publix", "walmart", ...) — lets
    /// the backend prompt tailor its expectations. Optional/additive.
    let storeChainHint: String?

    /// Short "ABBREV -> expansion" strings already resolved deterministically
    /// on-device (ReceiptItemResolver) so the structuring prompt can prefer
    /// them instead of re-guessing. Optional/additive.
    let dictionaryHints: [String]?

    init(
        rawText: String?,
        imageBase64: String?,
        imageMediaType: String?,
        storeHint: String?,
        storeChainHint: String? = nil,
        dictionaryHints: [String]? = nil
    ) {
        self.rawText = rawText
        self.imageBase64 = imageBase64
        self.imageMediaType = imageMediaType
        self.storeHint = storeHint
        self.storeChainHint = storeChainHint
        self.dictionaryHints = dictionaryHints
    }

    enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
        case imageBase64 = "image_base64"
        case imageMediaType = "image_media_type"
        case storeHint = "store_hint"
        case storeChainHint = "store_chain_hint"
        case dictionaryHints = "dictionary_hints"
    }
}

// MARK: - ReceiptStructuringResponse

struct ReceiptStructuringResponse: Codable, Sendable {
    let store: String
    let purchaseDate: Date?
    let totalAmount: Double?
    let taxAmount: Double?
    let paymentMethod: String?
    let lineItems: [Item]
    /// Server-side average confidence across all items (0.0–1.0).
    let confidence: Double
    /// Provider that produced the structuring ("haiku_vision", "vision_and_haiku").
    let provider: String
    /// Optional free-text notes from the model (skipped sections, low-confidence warnings).
    let notes: String?

    /// Printed subtotal (pre-tax). Additive/optional — an old backend that
    /// doesn't send this simply omits the key and decoding still succeeds.
    let subtotalAmount: Double?
    /// Printed total savings line ("SAVINGS: $14.36").
    let savingsAmount: Double?
    /// Order-level coupon amount not tied to a single item.
    let couponTotal: Double?
    /// 3-letter ISO-ish currency code ("USD", "EUR", "GBP"...).
    let currency: String?
    /// Normalized chain slug the model inferred ("publix", "walmart", "unknown"...).
    let storeChain: String?

    struct Item: Codable, Sendable {
        let rawText: String
        let canonicalFoodName: String
        let displayName: String
        let quantity: Double
        let unit: String
        let quantityGrams: Double?
        let unitPrice: Double?
        let totalPrice: Double
        let pricePerKg: Double?
        let onSale: Bool
        let saleNote: String?
        let confidence: Double

        /// Household/pharmacy/gift-card/etc — not a pantry food item.
        let isNonFood: Bool?
        /// Deposit/CRV/bag fee — not food, not a discount either.
        let isFee: Bool?
        /// Printed tax flag as-is ("F", "T", "FT", "N"...).
        let taxFlag: String?
        /// Department/category header seen nearest above this line ("PRODUCE"...).
        let categoryHint: String?
        /// Per-line discount already folded into totalPrice, surfaced separately for display.
        let lineDiscount: Double?

        enum CodingKeys: String, CodingKey {
            case rawText = "raw_text"
            case canonicalFoodName = "canonical_food_name"
            case displayName = "display_name"
            case quantity
            case unit
            case quantityGrams = "quantity_grams"
            case unitPrice = "unit_price"
            case totalPrice = "total_price"
            case pricePerKg = "price_per_kg"
            case onSale = "on_sale"
            case saleNote = "sale_note"
            case confidence
            case isNonFood = "is_non_food"
            case isFee = "is_fee"
            case taxFlag = "tax_flag"
            case categoryHint = "category_hint"
            case lineDiscount = "line_discount"
        }
    }

    enum CodingKeys: String, CodingKey {
        case store
        case purchaseDate = "purchase_date"
        case totalAmount = "total_amount"
        case taxAmount = "tax_amount"
        case paymentMethod = "payment_method"
        case lineItems = "line_items"
        case confidence
        case provider
        case notes
        case subtotalAmount = "subtotal_amount"
        case savingsAmount = "savings_amount"
        case couponTotal = "coupon_total"
        case currency
        case storeChain = "store_chain"
    }
}
