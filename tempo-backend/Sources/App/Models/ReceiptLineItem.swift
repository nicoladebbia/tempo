import Fluent
import Foundation
import Vapor

// MARK: - Receipt Line Item Fluent Model

final class ReceiptLineItem: Model, Content, @unchecked Sendable {
    static let schema = "receipt_line_items"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Parent(key: "receipt_id")
    var receipt: Receipt

    @Field(key: "raw_text")
    var rawText: String

    @Field(key: "canonical_food_name")
    var canonicalFoodName: String

    @Field(key: "display_name")
    var displayName: String

    @Field(key: "quantity")
    var quantity: Double

    @Field(key: "unit")
    var unit: String

    @OptionalField(key: "quantity_grams")
    var quantityGrams: Double?

    @OptionalField(key: "unit_price")
    var unitPrice: Double?

    @Field(key: "total_price")
    var totalPrice: Double

    @OptionalField(key: "price_per_kg")
    var pricePerKg: Double?

    @Field(key: "on_sale")
    var onSale: Bool

    @OptionalField(key: "sale_note")
    var saleNote: String?

    @Field(key: "confidence")
    var confidence: Double

    @Field(key: "user_confirmed")
    var userConfirmed: Bool

    @OptionalField(key: "linked_pantry_item_id")
    var linkedPantryItemID: String?

    @Field(key: "created_at")
    var createdAt: Date

    init() {}

    init(
        id: String = UUID().uuidString,
        receiptID: String,
        rawText: String,
        canonicalFoodName: String,
        displayName: String,
        quantity: Double,
        unit: String,
        totalPrice: Double,
        confidence: Double
    ) {
        self.id = id
        self.$receipt.id = receiptID
        self.rawText = rawText
        self.canonicalFoodName = canonicalFoodName
        self.displayName = displayName
        self.quantity = quantity
        self.unit = unit
        self.totalPrice = totalPrice
        self.onSale = false
        self.confidence = confidence
        self.userConfirmed = false
        self.createdAt = Date()
    }
}
