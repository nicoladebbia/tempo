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
        // `.tooLowQuality` is a distinct, user-actionable failure (blurry/
        // glare/faded photo even after the contrast retry) — surfaced to the
        // caller (ReceiptCaptureView) with a specific retake prompt instead
        // of silently falling back to the image-only path, since a photo bad
        // enough to fail Vision's own quality gate is usually bad enough to
        // fail Haiku Vision too.
        var rawText: String?
        var visionAvgConfidence: Double = 0
        var preParse: ReceiptPreParseResult?
        do {
            let visionResult = try await VisionReceiptOCR.recognize(image: image)
            rawText = visionResult.rawText
            visionAvgConfidence = visionResult.averageConfidence
            preParse = ReceiptPreParser.parse(rows: visionResult.rows, storeHint: storeHint)
        } catch let VisionReceiptOCRError.tooLowQuality(hint) {
            logger.warning("Receipt photo failed quality gate: \(hint, privacy: .public)")
            throw ReceiptServiceError.visionFailed(hint)
        } catch {
            logger.warning("Vision OCR failed, falling back to image-only Haiku: \(error.localizedDescription, privacy: .public)")
        }

        // Strip payment-card/auth/loyalty PII from the raw OCR text before it
        // is either sent to the backend or persisted to SwiftData. Safe to
        // run even when rawText is nil.
        if let text = rawText {
            rawText = ReceiptPrivacyRedactor.redact(text)
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

        // Duplicate-scan detection: compare this scan's store|date|total
        // fingerprint against every other receipt already on file. We don't
        // block the scan — just flag it so the review screen can warn before
        // the user ingests the same trip twice.
        if let key = preParse?.duplicateKey {
            stubReceipt.duplicateKey = key
            if let existing = try? fetchAll(),
               existing.contains(where: { $0.id != stubReceipt.id && $0.duplicateKey == key })
            {
                logger.warning("Possible duplicate receipt scan detected (key=\(key, privacy: .private))")
            }
        }
        try modelContext.save()

        // 4) Structure it (network + apply). Shared with retryStructuring().
        try await applyStructuring(
            to: stubReceipt,
            rawText: rawText,
            jpeg: downsampled,
            storeHint: storeHint,
            preParse: preParse
        )
        return stubReceipt
    }

    /// `true` when another receipt on file shares this one's store|date|total
    /// fingerprint — surfaced by the review UI as a "you may have already
    /// scanned this receipt" warning. Non-blocking by design.
    func isLikelyDuplicate(_ receipt: Receipt) -> Bool {
        guard let key = receipt.duplicateKey else {
            return false
        }
        let others = (try? fetchAll()) ?? []
        return others.contains { $0.id != receipt.id && $0.duplicateKey == key }
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
        storeHint: String?,
        preParse: ReceiptPreParseResult? = nil
    ) async throws {
        let base64 = jpeg.base64EncodedString()
        logger
            .info("[Diag.Receipt] upload payload jpeg=\(jpeg.count / 1024)KB base64=\(base64.count / 1024)KB hasOCRText=\(rawText != nil)")

        // Fold the deterministic pre-parse's "DETECTED totals" block into the
        // raw text so the structuring prompt can lean on numbers we already
        // trust (subtotal/tax/total/savings/voided-items boundary) instead of
        // re-deriving them from scratch. Additive — an old backend that
        // ignores the extra lines still works exactly as before.
        var textForRequest = rawText
        if let hints = preParse?.hintsBlock, !hints.isEmpty {
            textForRequest = [rawText, hints].compactMap(\.self).joined(separator: "\n\n")
        }

        let chainHint = Self.storeChainSlug(from: preParse?.storeNameGuess ?? storeHint)
        let dictionaryHints = preParse?.departmentHints.isEmpty == false ? preParse?.departmentHints : nil

        let request = ReceiptStructuringRequest(
            rawText: textForRequest,
            imageBase64: base64,
            imageMediaType: "image/jpeg",
            storeHint: storeHint,
            storeChainHint: chainHint,
            dictionaryHints: dictionaryHints
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
        // New/optional fields: prefer what the backend sent, fall back to the
        // deterministic pre-parse's own reading of the printed totals so an
        // older backend (or a Haiku response that omits them) doesn't leave
        // these blank.
        receipt.subtotalAmount = response.subtotalAmount ?? preParse?.subtotalAmount
        receipt.savingsAmount = response.savingsAmount ?? preParse?.savingsAmount
        receipt.currencyCode = response.currency ?? preParse?.currencyCode
        receipt.storeChain = response.storeChain ?? Self.storeChainSlug(from: response.store)
        receipt.updatedAt = Date()

        // Index the pre-parse's candidate items by raw text so per-line
        // deterministic hints (non-food/fee/tax-flag) can back-fill anything
        // the structuring response left nil — best-effort exact-text match
        // only; a miss just means we rely on the response alone for that line.
        // Keyed by REDACTED text: preParse was built from the unredacted
        // Vision rows, but itemDTO.rawText reflects what Haiku actually saw
        // (the redacted textForRequest) — without redacting the key too,
        // any row with an embedded barcode/reference number would never
        // match and silently lose its non-food/fee/tax-flag back-fill.
        let preParseByRawText: [String: ReceiptPreParseItemRow] = Dictionary(
            (preParse?.candidateItems ?? []).map { (ReceiptPrivacyRedactor.redact($0.rawText), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var itemTotals: [Double] = []
        for itemDTO in response.lineItems {
            let unit = ReceiptLineUnit(rawValue: itemDTO.unit) ?? .unit
            let preParseMatch = preParseByRawText[itemDTO.rawText]

            // Layer 1/2 of ReceiptItemResolver: a learned alias (the user
            // corrected this exact raw text at this store chain before) wins
            // outright over whatever Haiku guessed this time — that's the
            // whole point of "applied automatically with exact confidence".
            // Dictionary-only resolutions are NOT preferred over Haiku's own
            // (usually equally good, often better with visual context)
            // reading — they only fill in when Haiku left the name
            // unexpanded (still looks like the raw OCR text).
            let resolved = ReceiptItemResolver.resolve(
                rawText: itemDTO.rawText,
                storeChain: receipt.storeChain,
                in: modelContext
            )
            var resolvedDisplayName = itemDTO.displayName
            var resolvedCanonical = itemDTO.canonicalFoodName
            if resolved.confidence == .exactProduct {
                resolvedDisplayName = resolved.readableName
                resolvedCanonical = resolved.canonicalFoodName
            } else if resolved.confidence == .foodLevel,
                      itemDTO.displayName.trimmingCharacters(in: .whitespaces)
                      .caseInsensitiveCompare(itemDTO.rawText.trimmingCharacters(in: .whitespaces)) == .orderedSame
            {
                resolvedDisplayName = resolved.readableName
                resolvedCanonical = resolved.canonicalFoodName
            }

            let line = ReceiptLineItem(
                receipt: receipt,
                rawText: itemDTO.rawText,
                canonicalFoodName: resolvedCanonical,
                displayName: resolvedDisplayName,
                quantity: itemDTO.quantity,
                unit: unit,
                quantityGrams: itemDTO.quantityGrams,
                unitPrice: itemDTO.unitPrice,
                totalPrice: itemDTO.totalPrice,
                pricePerKg: itemDTO.pricePerKg,
                onSale: itemDTO.onSale,
                saleNote: itemDTO.saleNote,
                confidence: itemDTO.confidence,
                isNonFood: itemDTO.isNonFood ?? preParseMatch?.nonFoodHint ?? false,
                isFee: itemDTO.isFee ?? preParseMatch?.feeHint ?? false,
                taxFlag: itemDTO.taxFlag ?? preParseMatch?.taxFlag,
                categoryHint: itemDTO.categoryHint,
                lineDiscount: itemDTO.lineDiscount ?? preParseMatch?.promotionAdjustment
            )
            modelContext.insert(line)
            itemTotals.append(itemDTO.totalPrice)
        }

        // Post-structuring math cross-check: does sum(items) reconcile with
        // the printed subtotal/tax/total? Prefer the response's own totals,
        // fall back to the pre-parse's reading when the response omitted them.
        let crossCheck = ReceiptCrossChecker.check(
            itemTotals: itemTotals,
            subtotal: receipt.subtotalAmount,
            tax: receipt.taxAmount,
            total: receipt.totalAmount > 0 ? receipt.totalAmount : preParse?.totalAmount
        )
        receipt.crossCheckBanner = crossCheck.bannerMessage
        if let banner = crossCheck.bannerMessage {
            logger.warning("[Diag.Receipt] cross-check: \(banner, privacy: .public)")
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

        // The original Vision `rows` (column-aware) aren't persisted — only
        // the flattened rawText survives a retry. Degrade gracefully: wrap
        // each stored line as a single-column row so ReceiptPreParser can
        // still extract totals/voided-items/tax-flags, just without the
        // continuation-line (weight/qty) pairing that needs true column data.
        let degradedRows = (receipt.ocrRawText ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { VisionReceiptOCRResult.Row(columns: [$0], yPosition: 0, confidence: 1) }
        let preParse = degradedRows.isEmpty ? nil : ReceiptPreParser.parse(
            rows: degradedRows,
            storeHint: receipt.store.isEmpty || receipt.store == "Unknown" ? nil : receipt.store
        )

        try await applyStructuring(
            to: receipt,
            rawText: receipt.ocrRawText,
            jpeg: jpeg,
            storeHint: receipt.store.isEmpty || receipt.store == "Unknown" ? nil : receipt.store,
            preParse: preParse
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

    /// Best-effort normalized chain slug from a free-text store name/header
    /// ("Publix Super Market #1234" -> "publix"). Used as a hint for the
    /// backend's store-brand dictionaries; unknown chains just fall through
    /// with no hint, which is exactly today's behavior.
    private static let knownChains: [(slug: String, keywords: [String])] = [
        ("publix", ["publix"]),
        ("walmart", ["walmart", "wal-mart"]),
        ("target", ["target"]),
        ("costco", ["costco"]),
        ("kroger", ["kroger"]),
        ("wholefoods", ["whole foods", "wholefds"]),
        ("traderjoes", ["trader joe"]),
        ("aldi", ["aldi"]),
        ("esselunga", ["esselunga"]),
        ("conad", ["conad"]),
        ("coop", ["coop", "ipercoop"]),
    ]

    static func storeChainSlug(from text: String?) -> String? {
        guard let text, !text.isEmpty else {
            return nil
        }
        let lower = text.lowercased()
        for chain in knownChains where chain.keywords.contains(where: lower.contains) {
            return chain.slug
        }
        return nil
    }
}

// MARK: - APIEndpoint extension

extension APIEndpoint where Response == ReceiptStructuringResponse {
    static func receiptStructure() -> Self {
        APIEndpoint(path: "/v1/nutrition/receipts/structure", method: .post)
    }
}
