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

    enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
        case imageBase64 = "image_base64"
        case imageMediaType = "image_media_type"
        case storeHint = "store_hint"
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
    }
}
