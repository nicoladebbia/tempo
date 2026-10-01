//
// NutritionReviewFixesTests.swift
// Tempo
//
// Regression tests for the Round 1 review findings (spend counting, pantry
// piece weights, keyword matching, formatter overflow).
//

import Foundation
@testable import Tempo
import XCTest

final class NutritionReviewFixesTests: XCTestCase {
    private func lineItem(ingested: Bool) -> ReceiptLineItem {
        ReceiptLineItem(
            rawText: "RICE",
            canonicalFoodName: "rice",
            displayName: "Rice",
            quantity: 1,
            unit: .unit,
            totalPrice: 10,
            linkedPantryItemID: ingested ? UUID() : nil
        )
    }

    func testSpendCountsReceiptWithIngestedLineEvenIfNotReviewed() {
        let r = Receipt(store: "Publix", purchaseDate: Date(), totalAmount: 40)
        r.lineItems = [lineItem(ingested: true), lineItem(ingested: false)]
        let result = GroceryWeeklySpendCalculator.compute(
            priceEntries: [], receipts: [r], weeks: 1, budgetCapUSD: 100
        )
        XCTAssertEqual(result.last?.totalUSD ?? 0, 40, accuracy: 0.001)
    }

    func testSpendCountsConfirmedReceipt() {
        let r = Receipt(store: "Publix", purchaseDate: Date(), totalAmount: 25, ocrStatus: .confirmed)
        let result = GroceryWeeklySpendCalculator.compute(
            priceEntries: [], receipts: [r], weeks: 1, budgetCapUSD: 100
        )
        XCTAssertEqual(result.last?.totalUSD ?? 0, 25, accuracy: 0.001)
    }

    func testFailedScanDoesNotCancelRealRescan() {
        let now = Date()
        let failed = Receipt(
            store: "Publix", purchaseDate: now, totalAmount: 30, ocrStatus: .failed, duplicateKey: "k"
        )
        failed.createdAt = now.addingTimeInterval(-60)
        let real = Receipt(
            store: "Publix", purchaseDate: now, totalAmount: 30, userReviewed: true, duplicateKey: "k"
        )
        real.createdAt = now
        let result = GroceryWeeklySpendCalculator.compute(
            priceEntries: [], receipts: [failed, real], weeks: 1, budgetCapUSD: 100
        )
        XCTAssertEqual(result.last?.totalUSD ?? 0, 30, accuracy: 0.001)
    }

    func testPieceWeightUsesPurchaseGramsForLoafButNotEgg() throws {
        let bread = try XCTUnwrap(FoodMacroDatabase.naturalPortions["whole grain bread"])
        XCTAssertEqual(try XCTUnwrap(PantryUnit.pieces.gramsPerUnit(of: bread)), bread.purchaseGrams, accuracy: 0.001)
        let egg = try XCTUnwrap(FoodMacroDatabase.naturalPortions["egg"])
        XCTAssertEqual(try XCTUnwrap(PantryUnit.pieces.gramsPerUnit(of: egg)), 50, accuracy: 0.001)
    }

    func testCompoundKeywordsMatch() {
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "strawberries"), .fridge)
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "catfish"), .fridge)
        XCTAssertEqual(GroceryListGenerator.category(for: "catfish"), "seafood")
        XCTAssertEqual(GroceryListGenerator.category(for: "strawberries"), "produce")
        XCTAssertEqual(GroceryListGenerator.category(for: "oatmeal"), "grains")
        XCTAssertNotEqual(GroceryListGenerator.category(for: "orange juice"), "frozen")
        XCTAssertEqual(PantryStorageGuesser.guess(forName: "rice"), .pantry)
    }

    func testFormatterSurvivesHugeAndNonFiniteValues() {
        XCTAssertEqual(PantryQuantityFormatter.number(.nan), "0")
        XCTAssertEqual(PantryQuantityFormatter.number(.infinity), "0")
        XCTAssertEqual(PantryQuantityFormatter.number(1e19), "10000000000000000000")
        XCTAssertEqual(PantryQuantityFormatter.number(2), "2")
    }
}
