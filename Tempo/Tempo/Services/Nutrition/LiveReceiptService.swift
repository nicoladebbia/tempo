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
        // backend can recover when Vision text was empty or noisy — but
        // downsample it first. A full-res iPhone JPEG base64-encodes to ~2MB+
        // and trips the backend's request-body limit (413). 1568px is Claude's
        // max vision edge, so anything larger is bytes the model never reads.
        guard let downsampled = image.downsampledJPEGData() else {
            throw ReceiptServiceError.visionFailed("Could not encode receipt image.")
        }

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

        // Persist the downsampled JPEG to disk BEFORE the network call. If
        // structuring fails, retryStructuring() reloads these exact bytes —
        // the user never re-shoots the receipt. Best-effort: a failed write
        // only costs the retry affordance, not the scan itself.
        stubReceipt.photoPath = ReceiptPhotoStore.save(downsampled, for: stubReceipt.id)
        try modelContext.save()

        // 4) Structure it (network + apply). Shared with retryStructuring().
        try await applyStructuring(
            to: stubReceipt,
            rawText: rawText,
            jpeg: downsampled,
            storeHint: storeHint
        )
        return stubReceipt
    }

    // MARK: - Structuring (shared by scan + retry)

    /// POST the receipt to the backend and apply the parsed response onto an
    /// existing Receipt row. On any failure the row is marked `.failed` and the
    /// error rethrown — the row (and its persisted photo) survive so the user
    /// can retry. Reuses the row; never inserts a new Receipt.
    private func applyStructuring(
        to receipt: Receipt,
        rawText: String?,
        jpeg: Data,
        storeHint: String?
    ) async throws {
        let base64 = jpeg.base64EncodedString()
        logger.info("[Diag.Receipt] upload payload jpeg=\(jpeg.count / 1024)KB base64=\(base64.count / 1024)KB hasOCRText=\(rawText != nil)")

        let request = ReceiptStructuringRequest(
            rawText: rawText,
            imageBase64: base64,
            imageMediaType: "image/jpeg",
            storeHint: storeHint
        )

        let response: ReceiptStructuringResponse
        do {
            response = try await apiClient.request(
                APIEndpoint<ReceiptStructuringResponse>.receiptStructure(),
                body: request
            )
        } catch {
            receipt.ocrStatus = .failed
            receipt.updatedAt = Date()
            try? modelContext.save()
            // APIError.localizedDescription stringifies to "(Tempo.APIError
            // error 1.)" — useless to the user. Surface the friendly
            // .userMessage instead (covers 502, 413, truncation in one place).
            let message = (error as? APIError)?.userMessage ?? error.localizedDescription
            logger.error("[Diag.Receipt] structuring failed: \(error.localizedDescription, privacy: .public)")
            throw ReceiptServiceError.structuringFailed(message)
        }

        // Apply the response. On retry the row may already carry stale lines
        // from a prior partial run — clear them so we don't duplicate.
        for stale in receipt.orderedLineItems {
            modelContext.delete(stale)
        }
        receipt.store = response.store
        receipt.purchaseDate = response.purchaseDate ?? receipt.purchaseDate
        receipt.totalAmount = response.totalAmount ?? 0
        receipt.taxAmount = response.taxAmount
        receipt.paymentMethod = response.paymentMethod
        receipt.ocrStatus = .awaitingReview
        receipt.ocrProviderRaw = response.provider
        receipt.updatedAt = Date()

        for itemDTO in response.lineItems {
            let unit = ReceiptLineUnit(rawValue: itemDTO.unit) ?? .unit
            let line = ReceiptLineItem(
                receipt: receipt,
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
                sourceReceiptLineItemID: line.id,
                brand: ""
            )
            line.linkedPantryItemID = pantryItem.id

            // Record the price as a standalone history entry — one INSERT per
            // purchase, keyed by canonical food name so the time series
            // survives this item being consumed/archived and re-bought later.
            // mergeOrCreate may have MERGED into an existing item (quantity
            // summed); the price entry is independent of that so restocks
            // never overwrite prior prices. Only when the OCR actually parsed
            // a price (> 0) — a $0 line carries no signal.
            if line.totalPrice > 0 {
                let priceEntry = PantryPriceEntry(
                    canonicalFoodName: line.canonicalFoodName,
                    displayName: line.displayName.isEmpty ? line.canonicalFoodName : line.displayName,
                    purchaseDate: receipt.purchaseDate,
                    totalPaidUSD: line.totalPrice,
                    quantity: line.quantity,
                    unit: line.resolvedPantryUnit,
                    pricePerKg: line.pricePerKg,
                    source: .receiptScan,
                    store: receipt.store.isEmpty ? nil : receipt.store,
                    sourcePantryItemID: pantryItem.id,
                    sourceReceiptLineItemID: line.id
                )
                modelContext.insert(priceEntry)
            }
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

    func retryStructuring(_ receipt: Receipt) async throws {
        // Reload the JPEG we persisted at scan time. No re-shoot, no re-OCR:
        // the raw text is already on the row. Reuses the same Receipt row.
        guard let jpeg = ReceiptPhotoStore.load(for: receipt.id) else {
            // Photo never persisted (older receipt, or the write failed at
            // scan time). The only recourse is a fresh capture.
            throw ReceiptServiceError.structuringFailed("Re-capture the receipt to retry.")
        }
        receipt.ocrStatus = .processing
        receipt.updatedAt = Date()
        try modelContext.save()

        try await applyStructuring(
            to: receipt,
            rawText: receipt.ocrRawText,
            jpeg: jpeg,
            storeHint: receipt.store.isEmpty || receipt.store == "Unknown" ? nil : receipt.store
        )
    }

    // MARK: - Delete

    func delete(_ receipt: Receipt) throws {
        // SwiftData's cascade rule removes the rows but NOT the photo file on
        // disk — without this, every delete leaks an image in Application Support.
        ReceiptPhotoStore.delete(for: receipt.id)
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
