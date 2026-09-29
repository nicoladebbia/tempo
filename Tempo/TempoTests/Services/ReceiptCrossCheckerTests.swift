//
// ReceiptCrossCheckerTests.swift
// Tempo
//
// Covers the post-structuring math cross-check: consistent receipts produce
// no banner, a subtotal mismatch and a total mismatch each produce a
// specific banner, the items-vs-total fallback kicks in when subtotal/tax
// are unknown, and the "closest single culprit" heuristic only fires when a
// line price plausibly explains the whole delta.
//

@testable import Tempo
import XCTest

final class ReceiptCrossCheckerTests: XCTestCase {
    func test_consistentReceipt_noBanner() {
        let result = ReceiptCrossChecker.check(
            itemTotals: [4.99, 0.69, 8.99],
            subtotal: 14.67,
            tax: 0.86,
            total: 15.53
        )
        XCTAssertTrue(result.isConsistent)
        XCTAssertNil(result.bannerMessage)
    }

    func test_subtotalMismatch_producesBanner() {
        let result = ReceiptCrossChecker.check(
            itemTotals: [4.99, 0.69, 8.99],
            subtotal: 12.00,
            tax: nil,
            total: nil
        )
        XCTAssertFalse(result.isConsistent)
        XCTAssertNotNil(result.bannerMessage)
        XCTAssertTrue(result.bannerMessage?.contains("Check these lines") ?? false)
    }

    func test_subtotalPlusTaxMismatch_vsTotal_producesBanner() {
        let result = ReceiptCrossChecker.check(
            itemTotals: [10.00],
            subtotal: 10.00,
            tax: 0.70,
            total: 11.50 // should be 10.70
        )
        XCTAssertFalse(result.isConsistent)
        XCTAssertNotNil(result.totalDelta)
    }

    func test_withinTolerance_noBanner() {
        // 3 cents of rounding noise across a multi-item receipt is expected,
        // not a real mismatch.
        let result = ReceiptCrossChecker.check(
            itemTotals: [4.99, 0.69, 8.99],
            subtotal: 14.70, // real sum is 14.67
            tax: nil,
            total: nil,
            toleranceCents: 0.50
        )
        XCTAssertTrue(result.isConsistent)
    }

    func test_noSubtotalOrTax_fallsBackToItemsVsTotal() {
        let result = ReceiptCrossChecker.check(
            itemTotals: [4.99, 0.69],
            subtotal: nil,
            tax: nil,
            total: 20.00 // wildly off
        )
        XCTAssertFalse(result.isConsistent)
        XCTAssertNotNil(result.bannerMessage)
    }

    func test_noTotalsAtAll_consistentByDefault() {
        // Nothing to check against — we don't fabricate a mismatch.
        let result = ReceiptCrossChecker.check(
            itemTotals: [4.99, 0.69],
            subtotal: nil,
            tax: nil,
            total: nil
        )
        XCTAssertTrue(result.isConsistent)
    }

    func test_closestCulprit_identifiedWhenOneLineExplainsTheDelta() {
        // Items sum to 15.98 but subtotal says 8.99 -> a $6.99 line is the
        // most plausible single culprit (e.g. a duplicated/misread line).
        let result = ReceiptCrossChecker.check(
            itemTotals: [8.99, 6.99],
            subtotal: 8.99,
            tax: nil,
            total: nil
        )
        XCTAssertEqual(result.likelyCulpritIndex, 1)
    }

    func test_closestCulprit_nilWhenNoSingleLineExplainsDelta() {
        let result = ReceiptCrossChecker.check(
            itemTotals: [1.00, 2.00, 3.00],
            subtotal: 100.00,
            tax: nil,
            total: nil
        )
        XCTAssertNil(result.likelyCulpritIndex)
    }
}
