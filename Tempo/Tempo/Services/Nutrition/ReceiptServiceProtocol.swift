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

    /// Fetch all receipts (most-recent first).
    func fetchAll() throws -> [Receipt]

    /// Update a single line item (typically: user-edited canonical name / quantity / unit).
    /// Sets the line's userConfirmed flag to true.
    func confirmLineItem(_ line: ReceiptLineItem) throws

    /// Ingest every confirmed line item on a receipt into the pantry.
    /// Skips lines that have already been ingested (linkedPantryItemID != nil).
    /// Marks the receipt status as .confirmed when all lines are ingested.
    func ingestConfirmedLines(of receipt: Receipt, into pantry: any PantryServiceProtocol) throws

    /// Retry structuring on a previously failed receipt.
    func retryStructuring(_ receipt: Receipt) async throws

    /// Delete a receipt (cascade-deletes its line items, but does NOT undo
    /// pantry ingestions — those are independent rows once created).
    func delete(_ receipt: Receipt) throws
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
