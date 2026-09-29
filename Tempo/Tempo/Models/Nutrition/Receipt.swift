//
// Receipt.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - ReceiptOCRStatus

enum ReceiptOCRStatus: String, Codable, CaseIterable, Sendable {
    /// Raw text captured but not yet structured.
    case pending
    /// Structuring request in flight.
    case processing
    /// Line items extracted; awaiting user confirmation.
    case awaitingReview = "awaiting_review"
    /// User confirmed and ingested into pantry.
    case confirmed
    /// Structuring failed (network, parse error). User can retry.
    case failed
}

// MARK: - ReceiptOCRProvider

enum ReceiptOCRProvider: String, Codable, CaseIterable, Sendable {
    /// Apple Vision (`VNRecognizeTextRequest`) for on-device text extraction,
    /// then Claude Haiku for structuring the raw text into line items.
    case visionAndHaiku = "vision_and_haiku"
    /// Pure Claude Haiku Vision (image → structured items). Fallback when
    /// Vision recognition confidence is low.
    case haikuVision = "haiku_vision"
    /// Manual entry — no AI involved.
    case manual
}

// MARK: - Receipt

@Model
final class Receipt {
    @Attribute(.unique)
    var id: UUID

    /// Store name as recognized from the receipt header.
    var store: String

    /// Optional store branch/location string.
    var storeLocation: String?

    /// Receipt purchase date (parsed from the OCR'd date, fallback to scan time).
    var purchaseDate: Date

    /// Sum on the receipt — totalled by the receipt printer, not by us.
    var totalAmount: Double

    /// Sales tax line if present.
    var taxAmount: Double?

    /// Payment method as printed (e.g. "VISA ****1234", "CASH").
    var paymentMethod: String?

    /// Local file path or backend URL for the receipt photo.
    var photoPath: String?

    /// Current OCR pipeline state.
    var ocrStatusRaw: String

    /// Full raw text extracted by Vision (kept for re-parsing if structuring fails).
    var ocrRawText: String?

    /// Which provider structured this receipt.
    var ocrProviderRaw: String

    /// `true` once the user has reviewed every line and approved ingest.
    var userReviewed: Bool

    /// Printed subtotal (pre-tax). Optional/additive — nil for receipts
    /// scanned before this field existed or when the printer omitted it.
    var subtotalAmount: Double?

    /// Printed total savings line ("SAVINGS: $14.36").
    var savingsAmount: Double?

    /// 3-letter currency code detected from the receipt ("USD", "EUR"...).
    var currencyCode: String?

    /// Normalized chain slug ("publix", "walmart", "unknown"...).
    var storeChain: String?

    /// `ReceiptPreParseResult.duplicateKey` fingerprint ("store|date|total")
    /// computed at scan time — used to warn the user before they ingest the
    /// same receipt twice.
    var duplicateKey: String?

    /// `true` when this receipt was flagged as a likely duplicate of an
    /// earlier scan at ingest time. The user can dismiss the warning; we
    /// don't block ingest, only flag it.
    var duplicateWarningDismissed: Bool = false

    /// Human-readable banner from `ReceiptCrossChecker` when the printed
    /// totals don't reconcile with the line items ("Check these lines —
    /// items add up to $145.10 but the receipt subtotal is $142.32...").
    /// nil when the receipt is consistent or hasn't been checked yet.
    var crossCheckBanner: String?

    /// Timestamps.
    var createdAt: Date
    var updatedAt: Date

    /// Cascade: deleting a receipt deletes its line items.
    @Relationship(deleteRule: .cascade, inverse: \ReceiptLineItem.receipt)
    var lineItems: [ReceiptLineItem]?

    // MARK: - Computed

    @Transient
    var ocrStatus: ReceiptOCRStatus {
        get { ReceiptOCRStatus(rawValue: ocrStatusRaw) ?? .pending }
        set { ocrStatusRaw = newValue.rawValue }
    }

    @Transient
    var ocrProvider: ReceiptOCRProvider {
        get { ReceiptOCRProvider(rawValue: ocrProviderRaw) ?? .manual }
        set { ocrProviderRaw = newValue.rawValue }
    }

    @Transient
    var orderedLineItems: [ReceiptLineItem] {
        (lineItems ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    @Transient
    var lineItemCount: Int {
        lineItems?.count ?? 0
    }

    @Transient
    var confirmedLineItemCount: Int {
        (lineItems ?? []).filter(\.userConfirmed).count
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        store: String,
        storeLocation: String? = nil,
        purchaseDate: Date,
        totalAmount: Double,
        taxAmount: Double? = nil,
        paymentMethod: String? = nil,
        photoPath: String? = nil,
        ocrStatus: ReceiptOCRStatus = .pending,
        ocrRawText: String? = nil,
        ocrProvider: ReceiptOCRProvider = .visionAndHaiku,
        userReviewed: Bool = false,
        subtotalAmount: Double? = nil,
        savingsAmount: Double? = nil,
        currencyCode: String? = nil,
        storeChain: String? = nil,
        duplicateKey: String? = nil,
        duplicateWarningDismissed: Bool = false,
        crossCheckBanner: String? = nil
    ) {
        self.id = id
        self.store = store
        self.storeLocation = storeLocation
        self.purchaseDate = purchaseDate
        self.totalAmount = totalAmount
        self.taxAmount = taxAmount
        self.paymentMethod = paymentMethod
        self.photoPath = photoPath
        self.ocrStatusRaw = ocrStatus.rawValue
        self.ocrRawText = ocrRawText
        self.ocrProviderRaw = ocrProvider.rawValue
        self.userReviewed = userReviewed
        self.subtotalAmount = subtotalAmount
        self.savingsAmount = savingsAmount
        self.currencyCode = currencyCode
        self.storeChain = storeChain
        self.duplicateKey = duplicateKey
        self.duplicateWarningDismissed = duplicateWarningDismissed
        self.crossCheckBanner = crossCheckBanner
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}

// MARK: - DTO

extension Receipt {
    struct DTO: Codable, Sendable {
        let id: UUID
        let store: String
        let store_location: String?
        let purchase_date: Date
        let total_amount: Double
        let tax_amount: Double?
        let payment_method: String?
        let photo_path: String?
        let ocr_status: String
        let ocr_raw_text: String?
        let ocr_provider: String
        let user_reviewed: Bool
        let subtotal_amount: Double?
        let savings_amount: Double?
        let currency_code: String?
        let store_chain: String?
        let duplicate_key: String?
        let cross_check_banner: String?
        let created_at: Date
        let updated_at: Date
        let line_items: [ReceiptLineItem.DTO]
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            store: store,
            store_location: storeLocation,
            purchase_date: purchaseDate,
            total_amount: totalAmount,
            tax_amount: taxAmount,
            payment_method: paymentMethod,
            photo_path: photoPath,
            ocr_status: ocrStatusRaw,
            ocr_raw_text: ocrRawText,
            ocr_provider: ocrProviderRaw,
            user_reviewed: userReviewed,
            subtotal_amount: subtotalAmount,
            savings_amount: savingsAmount,
            currency_code: currencyCode,
            store_chain: storeChain,
            duplicate_key: duplicateKey,
            cross_check_banner: crossCheckBanner,
            created_at: createdAt,
            updated_at: updatedAt,
            line_items: orderedLineItems.map { $0.toDTO() }
        )
    }
}
