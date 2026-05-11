import Fluent
import Foundation
import Vapor

// MARK: - Receipt Fluent Model

final class Receipt: Model, Content, @unchecked Sendable {
    static let schema = "receipts"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "user_id")
    var userID: String

    @Field(key: "store")
    var store: String

    @OptionalField(key: "store_location")
    var storeLocation: String?

    @Field(key: "purchase_date")
    var purchaseDate: Date

    @Field(key: "total_amount")
    var totalAmount: Double

    @OptionalField(key: "tax_amount")
    var taxAmount: Double?

    @OptionalField(key: "payment_method")
    var paymentMethod: String?

    @OptionalField(key: "photo_path")
    var photoPath: String?

    @Field(key: "ocr_status")
    var ocrStatus: String

    @OptionalField(key: "ocr_raw_text")
    var ocrRawText: String?

    @Field(key: "ocr_provider")
    var ocrProvider: String

    @Field(key: "user_reviewed")
    var userReviewed: Bool

    @Field(key: "created_at")
    var createdAt: Date

    @Field(key: "updated_at")
    var updatedAt: Date

    @Children(for: \.$receipt)
    var lineItems: [ReceiptLineItem]

    init() {}

    init(
        id: String = UUID().uuidString,
        userID: String,
        store: String,
        purchaseDate: Date = Date(),
        totalAmount: Double = 0,
        ocrStatus: String = "pending",
        ocrProvider: String = "vision_and_haiku"
    ) {
        self.id = id
        self.userID = userID
        self.store = store
        self.purchaseDate = purchaseDate
        self.totalAmount = totalAmount
        self.ocrStatus = ocrStatus
        self.ocrProvider = ocrProvider
        self.userReviewed = false
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
