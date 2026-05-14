//
// LiveReceiptService.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import os
import SwiftData
import UIKit

// MARK: - LiveReceiptService

@MainActor
@Observable
final class LiveReceiptService: ReceiptServiceProtocol {
    private let modelContext: ModelContext
    private let apiClient: APIClient
    private let logger = Logger.nutrition

    init(modelContext: ModelContext, apiClient: APIClient) {
        self.modelContext = modelContext
        self.apiClient = apiClient
    }

    // MARK: - Scan

    @discardableResult
    func scan(image: UIImage, storeHint: String?) async throws -> Receipt {
        // 1) On-device Vision OCR. If it fails outright we fall through to the
        // image-only Haiku path; if it succeeds with low confidence we still
        // send both raw_text + image so the backend can choose.
        var rawText: String?
        var visionAvgConfidence: Double = 0
        do {
            let visionResult = try await VisionReceiptOCR.recognize(image: image)
            rawText = visionResult.rawText
            visionAvgConfidence = visionResult.averageConfidence
        } catch {
            logger.warning("Vision OCR failed, falling back to image-only Haiku: \(error.localizedDescription, privacy: .public)")
        }

        // 2) Prepare the structuring request. We always send the image so the
        // backend can recover when Vision text was empty or noisy.
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else {
            throw ReceiptServiceError.visionFailed("Could not encode receipt image.")
        }
        let base64 = jpeg.base64EncodedString()

        let request = ReceiptStructuringRequest(
            rawText: rawText,
            imageBase64: base64,
            imageMediaType: "image/jpeg",
            storeHint: storeHint
        )

        // 3) Persist a stub Receipt right away in .processing state, so the UI
        // can show progress. We'll update with parsed fields once the call returns.
        let stubReceipt = Receipt(
            store: storeHint ?? "Unknown",
            purchaseDate: Date(),
            totalAmount: 0,
            photoPath: nil,
            ocrStatus: .processing,
            ocrRawText: rawText,
            ocrProvider: rawText != nil && visionAvgConfidence > 0.5
                ? .visionAndHaiku
                : .haikuVision
        )
        modelContext.insert(stubReceipt)
        try modelContext.save()

        // 4) Call the backend structuring endpoint.
        let response: ReceiptStructuringResponse
        do {
            response = try await apiClient.request(
                APIEndpoint<ReceiptStructuringResponse>.receiptStructure(),
                body: request
            )
        } catch {
            stubReceipt.ocrStatus = .failed
            stubReceipt.updatedAt = Date()
            try? modelContext.save()
            logger.error("Structuring call failed: \(error.localizedDescription, privacy: .public)")
            throw ReceiptServiceError.structuringFailed(error.localizedDescription)
        }

        // 5) Apply the response onto the receipt + create line items.
        stubReceipt.store = response.store
        stubReceipt.purchaseDate = response.purchaseDate ?? stubReceipt.purchaseDate
        stubReceipt.totalAmount = response.totalAmount ?? 0
        stubReceipt.taxAmount = response.taxAmount
        stubReceipt.paymentMethod = response.paymentMethod
        stubReceipt.ocrStatus = .awaitingReview
        stubReceipt.ocrProviderRaw = response.provider
        stubReceipt.updatedAt = Date()

        for itemDTO in response.lineItems {
            let unit = ReceiptLineUnit(rawValue: itemDTO.unit) ?? .unit
            let line = ReceiptLineItem(
                receipt: stubReceipt,
                rawText: itemDTO.rawText,
                canonicalFoodName: itemDTO.canonicalFoodName,
                displayName: itemDTO.displayName,
                quantity: itemDTO.quantity,
                unit: unit,
                quantityGrams: itemDTO.quantityGrams,
                unitPrice: itemDTO.unitPrice,
                totalPrice: itemDTO.totalPrice,
                pricePerKg: itemDTO.pricePerKg,
                onSale: itemDTO.onSale,
                saleNote: itemDTO.saleNote,
                confidence: itemDTO.confidence
            )
            modelContext.insert(line)
        }
        try modelContext.save()
        logger
            .info(
                "Receipt structured: store=\(response.store, privacy: .public) lines=\(response.lineItems.count) avg_conf=\(response.confidence, format: .fixed(precision: 2))"
            )

        return stubReceipt
    }

    // MARK: - Fetch

    func fetchAll() throws -> [Receipt] {
        var descriptor = FetchDescriptor<Receipt>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Confirm + ingest

    func confirmLineItem(_ line: ReceiptLineItem) throws {
        line.userConfirmed = true
        try modelContext.save()
    }

    func ingestConfirmedLines(of receipt: Receipt, into pantry: any PantryServiceProtocol) throws {
        let confirmed = receipt.orderedLineItems.filter { $0.userConfirmed && !$0.isIngested }
        guard !confirmed.isEmpty else {
            throw ReceiptServiceError.noLinesToIngest
        }
        for line in confirmed {
            let pantryItem = try pantry.mergeOrCreate(
                rawName: line.displayName.isEmpty ? line.canonicalFoodName : line.displayName,
                quantity: line.quantity,
                unit: line.resolvedPantryUnit,
                storageLocation: defaultLocation(for: line.canonicalFoodName),
                purchaseDate: receipt.purchaseDate,
                purchaseSource: .receiptScan,
                sourceReceiptLineItemID: line.id
            )
            line.linkedPantryItemID = pantryItem.id
        }
        // Mark the receipt as confirmed if every line is now ingested.
        let stillUningested = receipt.orderedLineItems.filter { !$0.isIngested }
        if stillUningested.isEmpty {
            receipt.ocrStatus = .confirmed
            receipt.userReviewed = true
            receipt.updatedAt = Date()
        }
        try modelContext.save()
        logger.info("Receipt \(receipt.id) ingested \(confirmed.count) line(s) into pantry")
    }

    // MARK: - Retry

    func retryStructuring(_: Receipt) async throws {
        // V1: retry path requires the original photo, which we don't yet persist
        // to disk. Wired here as a TODO so callers can show a "rescan" affordance
        // that takes the user back to the camera flow.
        throw ReceiptServiceError.structuringFailed("Re-capture the receipt to retry.")
    }

    // MARK: - Delete

    func delete(_ receipt: Receipt) throws {
        modelContext.delete(receipt)
        try modelContext.save()
    }

    // MARK: - Helpers

    /// Heuristic default storage location based on canonical food name. Users
    /// can edit per-line in the review UI; this only seeds the initial value.
    private func defaultLocation(for canonical: String) -> PantryStorageLocation {
        // Items typically refrigerated.
        let fridgeKeywords = [
            "chicken", "salmon", "turkey", "beef", "yogurt", "milk", "cheese",
            "eggs", "fish", "spinach", "asparagus", "broccoli",
        ]
        // Items typically frozen.
        let freezerKeywords = ["frozen", "berries", "ice"]
        let name = canonical.lowercased()
        if freezerKeywords.contains(where: name.contains) {
            return .freezer
        }
        if fridgeKeywords.contains(where: name.contains) {
            return .fridge
        }
        return .pantry
    }
}

// MARK: - APIEndpoint extension

extension APIEndpoint where Response == ReceiptStructuringResponse {
    static func receiptStructure() -> Self {
        APIEndpoint(path: "/v1/nutrition/receipts/structure", method: .post)
    }
}
