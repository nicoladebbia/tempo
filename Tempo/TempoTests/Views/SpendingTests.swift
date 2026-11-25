//
// SpendingTests.swift
// Tempo
//
// The Spending page (receipts and weekly spend in one): which receipts open
// their review, how the eight weeks are read (average, weeks over budget, the
// week a tap picks) and the words under the numbers.
//

@testable import Tempo
import XCTest

@MainActor
final class SpendingTests: XCTestCase {
    // MARK: Receipts that open

    private func receipt(_ status: ReceiptOCRStatus) -> Receipt {
        let receipt = Receipt(store: "Publix", purchaseDate: Date(timeIntervalSince1970: 1_790_000_000), totalAmount: 42)
        receipt.ocrStatus = status
        return receipt
    }

    /// A "Needs review" receipt must always be tappable (it was a dead label), even when no lines were read.
    func testNeedsReviewAlwaysOpens() {
        XCTAssertTrue(SpendingView.canOpen(receipt(.awaitingReview)))
    }

    func testNothingToShowDoesNotOpen() {
        XCTAssertFalse(SpendingView.canOpen(receipt(.pending)))
        XCTAssertFalse(SpendingView.canOpen(receipt(.processing)))
        XCTAssertFalse(SpendingView.canOpen(receipt(.failed)))
        XCTAssertFalse(SpendingView.canOpen(receipt(.confirmed)), "confirmed with no lines")
    }

    // MARK: Weeks

    private let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5)) ?? Date()

    /// Eight weeks ending on `monday`, with these totals (oldest first) and a $100 budget.
    private func summary(_ totals: [Double], cap: Int? = 100) -> SpendingSummary {
        let weeks = totals.enumerated().map { index, total in
            GroceryWeeklySpend(
                weekStartDate: Calendar.current.date(byAdding: .weekOfYear, value: index - (totals.count - 1), to: monday) ?? monday,
                totalUSD: total,
                budgetCapUSD: cap
            )
        }
        return SpendingSummary(weeks: weeks)
    }

    func testAverageStartsAtTheFirstWeekWithSpend() throws {
        // Three empty weeks before the first shop must not drag the average down.
        let result = summary([0, 0, 0, 60, 100, 80, 0, 40])
        XCTAssertEqual(try XCTUnwrap(result.averagePerWeek), 56, accuracy: 0.001)
    }

    func testNoSpendHasNoAverageAndNoFooter() {
        let result = summary([0, 0, 0, 0])
        XCTAssertNil(result.averagePerWeek)
        XCTAssertNil(result.footer)
        XCTAssertFalse(result.hasSpend)
    }

    func testOverBudgetWeeksAreCounted() {
        XCTAssertEqual(summary([50, 120, 99, 101]).overBudgetWeeks, 2)
        XCTAssertEqual(summary([50, 120, 99, 101], cap: nil).overBudgetWeeks, 0, "no budget, nothing is over")
    }

    func testPickedWeekIsFoundAndAnUnknownOneFallsBackToThisWeek() {
        let result = summary([10, 20, 30, 40])
        let second = result.weeks[1]
        XCTAssertEqual(result.week(second.id)?.totalUSD, 20)
        XCTAssertEqual(result.week(nil)?.totalUSD, 40, "nothing picked reads this week")
        XCTAssertEqual(result.week(Date(timeIntervalSince1970: 1))?.totalUSD, 40, "a week that is not there reads this week")
        XCTAssertEqual(result.current?.totalUSD, 40)
    }

    func testMakeBucketsReceiptsAndPurchasesIntoEightWeeks() {
        let thursday = Calendar.current.date(byAdding: .day, value: 3, to: monday) ?? monday
        let confirmed = Receipt(store: "Publix", purchaseDate: thursday, totalAmount: 60, ocrStatus: .confirmed, userReviewed: true)
        let waiting = Receipt(store: "Publix", purchaseDate: thursday, totalAmount: 25, ocrStatus: .awaitingReview)
        let entry = PantryPriceEntry(
            canonicalFoodName: "rice", displayName: "Rice", purchaseDate: thursday,
            totalPaidUSD: 15, quantity: 1, unit: .packs
        )
        let result = SpendingSummary.make(
            receipts: [confirmed, waiting], priceEntries: [entry], budgetCapUSD: 70, now: thursday
        )
        XCTAssertEqual(result.weeks.count, SpendingSummary.weekCount)
        XCTAssertEqual(result.current?.totalUSD ?? -1, 75, accuracy: 0.001, "a receipt waiting for review is not spend yet")
        XCTAssertTrue(result.current?.isOverBudget ?? false)
    }

    // MARK: Words

    func testMoneyAlwaysHasTwoDecimals() {
        XCTAssertEqual(SpendingSummary.money(73.4), "$73.40")
        XCTAssertEqual(SpendingSummary.money(0), "$0.00")
    }

    func testBudgetLineSaysLeftOrOver() {
        let under = GroceryWeeklySpend(weekStartDate: monday, totalUSD: 73.45, budgetCapUSD: 120)
        let over = GroceryWeeklySpend(weekStartDate: monday, totalUSD: 134.55, budgetCapUSD: 120)
        let none = GroceryWeeklySpend(weekStartDate: monday, totalUSD: 50, budgetCapUSD: nil)
        XCTAssertEqual(SpendingSummary.budgetLine(under), "$46.55 left of your $120 budget")
        XCTAssertEqual(SpendingSummary.budgetLine(over), "$14.55 over your $120 budget")
        XCTAssertEqual(SpendingSummary.budgetLine(none), "No weekly budget set")
    }

    func testFooterPluralisesTheWeeksOverBudget() {
        XCTAssertEqual(summary([100, 100]).footer, "Average $100.00 a week")
        XCTAssertEqual(summary([50, 150]).footer, "Average $100.00 a week · 1 week over budget")
        XCTAssertEqual(summary([150, 150]).footer, "Average $150.00 a week · 2 weeks over budget")
    }

    func testBarsReadTheWeekTheTotalAndWhetherItIsOver() {
        let week = GroceryWeeklySpend(weekStartDate: monday, totalUSD: 134.55, budgetCapUSD: 120)
        let label = KitchenSpendTrend.accessibilityLabel(for: week)
        XCTAssertTrue(label.hasPrefix("Week of "))
        XCTAssertTrue(label.hasSuffix("$134.55, over budget"))
        let fine = KitchenSpendTrend.accessibilityLabel(for: GroceryWeeklySpend(weekStartDate: monday, totalUSD: 20, budgetCapUSD: 120))
        XCTAssertTrue(fine.hasSuffix("$20.00"))
    }
}
