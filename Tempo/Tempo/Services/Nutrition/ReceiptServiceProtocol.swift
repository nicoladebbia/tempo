//
// ReceiptServiceProtocol.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData
import UIKit

// MARK: - ReceiptServiceProtocol

@MainActor
protocol ReceiptServiceProtocol: Sendable {
    /// Run the full scan: Vision OCR → backend structuring → SwiftData persist.
    /// Returns the new Receipt (status = .awaitingReview on success, .failed on error).
    @discardableResult
    func scan(image: UIImage, storeHint: String?) async throws -> Receipt

    /// Multi-photo variant for long receipts that don't fit one frame: runs
    /// Vision OCR on every photo, stitches the rows into one reading-order
    /// stream, and drops rows that are a near-duplicate re-read of the same
    /// physical line at the seam between two consecutive shots (the user is
    /// expected to overlap shots slightly so nothing is missed). Only the
    /// FIRST photo is sent to the backend's image-fallback path — the full
    /// stitched text from every photo still reaches structuring via
    /// `rawText`. A single-element array behaves exactly like `scan(image:)`.
    @discardableResult
    func scan(images: [UIImage], storeHint: String?) async throws -> Receipt

    /// Fetch all receipts (most-recent first).
    func fetchAll() throws -> [Receipt]

    /// Ingest every confirmed line item on a receipt into the pantry.
    /// Skips lines that have already been ingested (linkedPantryItemID != nil).
    /// Marks the receipt status as .confirmed when all lines are ingested.
    func ingestConfirmedLines(of receipt: Receipt, into pantry: any PantryServiceProtocol) throws

    /// Same, with the review screen's per-line storage / expiry choices.
    func ingestConfirmedLines(
        of receipt: Receipt,
        into pantry: any PantryServiceProtocol,
        overrides: [UUID: ReceiptIngestOverride]
    ) throws

    /// Retry structuring on a previously failed receipt.
    func retryStructuring(_ receipt: Receipt) async throws

    /// Delete a receipt (cascade-deletes its line items, but does NOT undo
    /// pantry ingestions — those are independent rows once created).
    func delete(_ receipt: Receipt) throws

    /// `true` when another receipt on file shares this one's store|date|total
    /// fingerprint (`Receipt.duplicateKey`) — a likely re-scan of the same
    /// physical receipt. Non-blocking: the caller decides whether to warn.
    func isLikelyDuplicate(_ receipt: Receipt) -> Bool

    /// Records a user correction/confirmation of a line's name: learns it as
    /// a local alias (ReceiptItemResolver layer 2 — wins outright next time
    /// this exact raw text is seen at this store chain) AND best-effort
    /// contributes it to the shared backend crowd table
    /// (POST /v1/nutrition/receipt-aliases/confirm). The backend call is
    /// fire-and-forget: never blocks, never surfaces an error — the local
    /// alias is what matters on this device; the backend call only helps
    /// other users' devices over time.
    func confirmAlias(
        rawText: String,
        storeChain: String?,
        readableName: String,
        canonicalFoodName: String,
        barcode: String?
    )
}

// MARK: - ReceiptServiceError

enum ReceiptServiceError: Error, LocalizedError, Sendable {
    case visionFailed(String)
    case structuringFailed(String)
    case malformedResponse
    case noLinesToIngest

    var errorDescription: String? {
        switch self {
        case let .visionFailed(detail): "Vision OCR failed: \(detail)"
        case let .structuringFailed(detail): "Receipt structuring failed: \(detail)"
        case .malformedResponse: "Backend returned a malformed receipt response."
        case .noLinesToIngest: "No confirmed lines to add to the pantry."
        }
    }
}

extension ReceiptServiceProtocol {
    /// Services that don't honour per-line overrides just ingest as before.
    func ingestConfirmedLines(
        of receipt: Receipt,
        into pantry: any PantryServiceProtocol,
        overrides _: [UUID: ReceiptIngestOverride]
    ) throws {
        try ingestConfirmedLines(of: receipt, into: pantry)
    }
}
