//
// MockReceiptService.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import UIKit

@MainActor
@Observable
final class MockReceiptService: ReceiptServiceProtocol {
    private(set) var receipts: [Receipt] = []
    private var nextID: Int = 0

    /// When non-nil, scan() throws this error instead of producing a receipt.
    var simulatedScanError: Error?

    init() {}

    @discardableResult
    func scan(image _: UIImage, storeHint: String?) async throws -> Receipt {
        if let simulatedScanError {
            throw simulatedScanError
        }
        nextID += 1
        let receipt = Receipt(
            store: storeHint ?? "Publix",
            purchaseDate: Date(),
            totalAmount: 24.75,
            taxAmount: 1.50,
            paymentMethod: "VISA",
            ocrStatus: .awaitingReview,
            ocrRawText: "GV CHKN BRST 1.32LB 6.59\nATL SALMON FILLET 7.99\nBANANAS 0.69 LB 2.07\nFROZEN BLUEBERRIES 4.99",
            ocrProvider: .visionAndHaiku
        )
        receipt.lineItems = [
            ReceiptLineItem(
                receipt: receipt,
                rawText: "GV CHKN BRST 1.32LB 6.59",
                canonicalFoodName: "chicken breast",
                displayName: "Chicken Breast",
                quantity: 1.32, unit: .pounds, quantityGrams: 599,
                unitPrice: 4.99, totalPrice: 6.59, pricePerKg: 11.00,
                confidence: 0.93
            ),
            ReceiptLineItem(
                receipt: receipt,
                rawText: "ATL SALMON FILLET 7.99",
                canonicalFoodName: "salmon",
                displayName: "Atlantic Salmon Fillet",
                quantity: 1, unit: .each, quantityGrams: 200,
                unitPrice: 7.99, totalPrice: 7.99, pricePerKg: 39.95,
                confidence: 0.91
            ),
            ReceiptLineItem(
                receipt: receipt,
                rawText: "BANANAS 0.69 LB 2.07",
                canonicalFoodName: "banana",
                displayName: "Bananas",
                quantity: 3, unit: .pounds, quantityGrams: 1361,
                unitPrice: 0.69, totalPrice: 2.07, pricePerKg: 1.52,
                confidence: 0.96
            ),
            ReceiptLineItem(
                receipt: receipt,
                rawText: "FROZEN BLUEBERRIES 4.99",
                canonicalFoodName: "berries",
                displayName: "Blueberries",
                quantity: 1, unit: .each, quantityGrams: 340,
                unitPrice: 4.99, totalPrice: 4.99, pricePerKg: 14.68,
                onSale: true, saleNote: "2 for $8",
                confidence: 0.89
            ),
        ]
        receipts.insert(receipt, at: 0)
        return receipt
    }

    func fetchAll() throws -> [Receipt] {
        receipts
    }

    func confirmLineItem(_ line: ReceiptLineItem) throws {
        line.userConfirmed = true
    }

    func ingestConfirmedLines(of receipt: Receipt, into pantry: any PantryServiceProtocol) throws {
        let confirmed = receipt.orderedLineItems.filter { $0.userConfirmed && !$0.isIngested }
        guard !confirmed.isEmpty else {
            throw ReceiptServiceError.noLinesToIngest
        }
        for line in confirmed {
            let item = try pantry.mergeOrCreate(
                rawName: line.displayName.isEmpty ? line.canonicalFoodName : line.displayName,
                quantity: line.quantity,
                unit: line.resolvedPantryUnit,
                storageLocation: .pantry,
                purchaseDate: receipt.purchaseDate,
                purchaseSource: .receiptScan,
                sourceReceiptLineItemID: line.id,
                brand: ""
            )
            line.linkedPantryItemID = item.id
        }
        let stillUningested = receipt.orderedLineItems.filter { !$0.isIngested }
        if stillUningested.isEmpty {
            receipt.ocrStatus = .confirmed
            receipt.userReviewed = true
            receipt.updatedAt = Date()
        }
    }

    func retryStructuring(_: Receipt) async throws {}

    func delete(_ receipt: Receipt) throws {
        receipts.removeAll { $0.id == receipt.id }
    }
}
