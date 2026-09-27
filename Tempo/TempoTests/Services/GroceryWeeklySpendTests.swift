//
// GroceryWeeklySpendTests.swift
// Tempo
//
// BUILD item 4: weekly spend history — actual spend per week from
// PantryPriceEntry + Receipt totals, vs. the budget cap, for the last N weeks.
//

import Foundation
@testable import Tempo
import XCTest

final class GroceryWeeklySpendTests: XCTestCase {
    private let calendar = Calendar.current

    private func priceEntry(daysAgo: Double, usd: Double, receiptSourced: Bool = false) -> PantryPriceEntry {
        let entry = PantryPriceEntry(
            canonicalFoodName: "rice",
            displayName: "Rice",
            purchaseDate: Date().addingTimeInterval(-daysAgo * 86400),
            totalPaidUSD: usd,
            quantity: 1,
            unit: .packs
        )
        if receiptSourced {
            entry.sourceReceiptLineItemID = UUID()
        }
        return entry
    }

    private func receipt(daysAgo: Double, usd: Double) -> Receipt {
        Receipt(
            store: "Publix",
            purchaseDate: Date().addingTimeInterval(-daysAgo * 86400),
            totalAmount: usd
        )
    }

    func testCompute_returnsExactlyRequestedWeekCount() {
        let result = GroceryWeeklySpendCalculator.compute(
            priceEntries: [], receipts: [], weeks: 8, budgetCapUSD: 150
        )
        XCTAssertEqual(result.count, 8)
    }

    func testCompute_sumsManualEntriesIntoTheCurrentWeek() {
        let result = GroceryWeeklySpendCalculator.compute(
            priceEntries: [priceEntry(daysAgo: 0, usd: 20), priceEntry(daysAgo: 1, usd: 30)],
            receipts: [],
            weeks: 4,
            budgetCapUSD: nil
        )
        XCTAssertEqual(result.last?.totalUSD ?? -1, 50, accuracy: 0.01)
    }

    func testCompute_excludesReceiptSourcedPriceEntriesToAvoidDoubleCounting() {
        let result = GroceryWeeklySpendCalculator.compute(
            priceEntries: [priceEntry(daysAgo: 0, usd: 20, receiptSourced: true)],
            receipts: [receipt(daysAgo: 0, usd: 45)],
            weeks: 1,
            budgetCapUSD: nil
        )
        XCTAssertEqual(
            result.last?.totalUSD ?? -1,
            45,
            accuracy: 0.01,
            "Receipt-sourced price entry must not double the receipt's own total"
        )
    }

    func testCompute_bucketsOlderPurchasesIntoTheirOwnWeek() {
        let twoWeeksAgo = 15.0 // safely into "2 weeks ago" bucket regardless of today's weekday
        let result = GroceryWeeklySpendCalculator.compute(
            priceEntries: [priceEntry(daysAgo: twoWeeksAgo, usd: 40)],
            receipts: [],
            weeks: 4,
            budgetCapUSD: nil
        )
        let total = result.reduce(0) { $0 + $1.totalUSD }
        XCTAssertEqual(total, 40, accuracy: 0.01, "The purchase must land in exactly one week bucket")
        XCTAssertNotEqual(result.last?.totalUSD ?? 0, 40, "Not the current week — it's from 2 weeks ago")
    }

    func testCompute_purchasesOlderThanWindowAreExcluded() {
        let result = GroceryWeeklySpendCalculator.compute(
            priceEntries: [priceEntry(daysAgo: 400, usd: 999)],
            receipts: [],
            weeks: 4,
            budgetCapUSD: nil
        )
        XCTAssertEqual(result.reduce(0) { $0 + $1.totalUSD }, 0, "Way outside the 4-week window")
    }

    func testIsOverBudget_trueWhenTotalExceedsCap() {
        let week = GroceryWeeklySpend(weekStartDate: .now, totalUSD: 200, budgetCapUSD: 150)
        XCTAssertTrue(week.isOverBudget)
    }

    func testIsOverBudget_falseWhenNoCapSet() {
        let week = GroceryWeeklySpend(weekStartDate: .now, totalUSD: 200, budgetCapUSD: nil)
        XCTAssertFalse(week.isOverBudget)
    }

    func testIsOverBudget_falseWhenUnderCap() {
        let week = GroceryWeeklySpend(weekStartDate: .now, totalUSD: 100, budgetCapUSD: 150)
        XCTAssertFalse(week.isOverBudget)
    }
}
