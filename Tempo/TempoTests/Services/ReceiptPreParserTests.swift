//
// ReceiptPreParserTests.swift
// Tempo
//
// Covers ReceiptPreParser's deterministic construct detection: totals
// extraction, voided-items boundary, you-saved/promotion attachment,
// continuation (weight/qty) line pairing, tax-flag/non-food/fee heuristics,
// department headers, locale/currency detection, and the duplicate-key
// fingerprint. Rows are synthetic (hand-written, no real photo needed) since
// ReceiptPreParser.parse only consumes plain (columns, yPosition, confidence)
// data — no Vision/network dependency.
//

@testable import Tempo
import XCTest

final class ReceiptPreParserTests: XCTestCase {
    // MARK: - Helpers

    /// Builds rows top-to-bottom (yPosition descending, matching Vision's
    /// bottom-left-origin convention that VisionReceiptOCR.reconstructRows
    /// already sorted for us) from plain text lines, one column each unless
    /// `|` splits explicit columns.
    private func rows(_ lines: [String]) -> [VisionReceiptOCRResult.Row] {
        var y = 1.0
        return lines.map { line in
            defer { y -= 0.01 }
            let columns = line.components(separatedBy: "|")
            return VisionReceiptOCRResult.Row(columns: columns, yPosition: y, confidence: 0.95)
        }
    }

    // MARK: - Totals extraction

    func test_parsesSubtotalTaxTotalPaymentSavings() {
        let result = ReceiptPreParser.parse(rows: rows([
            "PUBLIX",
            "BANANAS|0.69",
            "Subtotal|12.34",
            "Sales Tax|0.86",
            "Total|13.20",
            "MASTERCARD|13.20",
            "You saved: $2.50",
        ]), storeHint: nil)

        XCTAssertEqual(result.subtotalAmount, 12.34)
        XCTAssertEqual(result.taxAmount, 0.86)
        XCTAssertEqual(result.totalAmount, 13.20)
        XCTAssertEqual(result.paymentAmount, 13.20)
        XCTAssertEqual(result.paymentMethod, "MasterCard")
        XCTAssertEqual(result.savingsAmount, 2.50)
    }

    // MARK: - Voided items

    func test_voidedItemsSection_excludedFromCandidateItems() {
        let result = ReceiptPreParser.parse(rows: rows([
            "MILK|2.99",
            "Voided Items",
            "EGGS|3.49",
            "BREAD|2.19",
            "Subtotal|2.99",
        ]), storeHint: nil)

        XCTAssertEqual(result.candidateItems.count, 1)
        XCTAssertTrue(result.candidateItems.first?.rawText.contains("MILK") ?? false)
        XCTAssertEqual(result.voidedItems.count, 2)
        XCTAssertTrue(result.voidedItems.contains { $0.rawText.contains("EGGS") })
    }

    func test_youSaved_insideVoidedSection_attachesToVoidedItem_notCandidate() {
        let result = ReceiptPreParser.parse(rows: rows([
            "MILK|2.99",
            "Voided Items",
            "EGGS|3.49",
            "You saved: $1.00",
        ]), storeHint: nil)

        XCTAssertNil(result.candidateItems.first?.youSaved)
        XCTAssertEqual(result.voidedItems.last?.youSaved, 1.00)
    }

    // MARK: - You saved / promotion attachment

    func test_youSaved_attachesToPrecedingItem() {
        let result = ReceiptPreParser.parse(rows: rows([
            "GREEK YOGURT|4.99",
            "You saved: $1.50",
            "BANANAS|0.69",
        ]), storeHint: nil)

        XCTAssertEqual(result.candidateItems.count, 2)
        XCTAssertEqual(result.candidateItems[0].youSaved, 1.50)
        XCTAssertNil(result.candidateItems[1].youSaved)
    }

    func test_promotionLine_attachesAdjustmentAndIsFlaggedAsDiscountLine() {
        let result = ReceiptPreParser.parse(rows: rows([
            "CHICKEN BRST|8.99",
            "Promotion|-2.00",
        ]), storeHint: nil)

        XCTAssertEqual(result.candidateItems.count, 2)
        XCTAssertEqual(result.candidateItems[0].promotionAdjustment, 2.00)
        XCTAssertTrue(result.candidateItems[1].isDiscountLine)
        XCTAssertEqual(result.candidateItems[1].totalPrice, -2.00)
    }

    // MARK: - Continuation lines (weight / multi-qty)

    func test_weightContinuationLine_pairsToItemAbove_whenItemHadNoPrice() {
        let result = ReceiptPreParser.parse(rows: rows([
            "BANANAS",
            "$0.59/lb x 2.36 lb|1.39",
        ]), storeHint: nil)

        XCTAssertEqual(result.candidateItems.count, 1)
        XCTAssertEqual(result.candidateItems[0].totalPrice, 1.39)
        XCTAssertNotNil(result.candidateItems[0].saleNote)
    }

    func test_multiQtyContinuationLine_pairsToItemAbove() {
        let result = ReceiptPreParser.parse(rows: rows([
            "OIKOS YOGURT 4PK",
            "3 @ 6.71|20.13",
        ]), storeHint: nil)

        XCTAssertEqual(result.candidateItems.count, 1)
        XCTAssertEqual(result.candidateItems[0].totalPrice, 20.13)
    }

    // MARK: - Tax flag / non-food / fee heuristics

    func test_taxFlagDetected_trailingToken() {
        let result = ReceiptPreParser.parse(rows: rows([
            "DOWNY SHEETS 6.99 T",
        ]), storeHint: nil)

        XCTAssertEqual(result.candidateItems.first?.taxFlag, "T")
    }

    func test_nonFoodKeyword_flagsNonFoodHint() {
        let result = ReceiptPreParser.parse(rows: rows([
            "DOWNY SHEETS|6.99",
        ]), storeHint: nil)

        XCTAssertTrue(result.candidateItems.first?.nonFoodHint ?? false)
    }

    func test_feeKeyword_flagsFeeHint() {
        let result = ReceiptPreParser.parse(rows: rows([
            "BOTTLE DEPOSIT|0.05",
        ]), storeHint: nil)

        XCTAssertTrue(result.candidateItems.first?.feeHint ?? false)
    }

    // MARK: - Department headers

    func test_departmentHeader_collectedAsHint_notAsItem() {
        let result = ReceiptPreParser.parse(rows: rows([
            "PRODUCE",
            "BANANAS|0.69",
            "DELI",
            "TURKEY SLICED|5.99",
        ]), storeHint: nil)

        XCTAssertEqual(result.departmentHints, ["PRODUCE", "DELI"])
        XCTAssertEqual(result.candidateItems.count, 2)
    }

    // MARK: - Locale / currency

    func test_euroSign_detectsEURCurrency() {
        let result = ReceiptPreParser.parse(rows: rows([
            "PANE|€2,49",
        ]), storeHint: nil)

        XCTAssertEqual(result.currencyCode, "EUR")
        XCTAssertTrue(result.isLikelyNonUSLocale)
    }

    func test_euCommaDecimalAmount_parsedCorrectly() {
        let result = ReceiptPreParser.parse(rows: rows([
            "Totale|1.234,56",
        ]), storeHint: nil)

        XCTAssertEqual(result.totalAmount ?? 0, 1234.56, accuracy: 0.001)
    }

    // MARK: - Duplicate key

    func test_duplicateKey_includesStoreDateAndTotal_whenBothPresent() {
        let result = ReceiptPreParser.parse(rows: rows([
            "PUBLIX",
            "09/15/2026",
            "BANANAS|0.69",
            "Total|13.20",
        ]), storeHint: "Publix")

        XCTAssertNotNil(result.duplicateKey)
        XCTAssertTrue(result.duplicateKey?.contains("13.20") ?? false)
        XCTAssertTrue(result.duplicateKey?.lowercased().contains("publix") ?? false)
    }

    func test_duplicateKey_nil_whenNoTotalFound() {
        let result = ReceiptPreParser.parse(rows: rows([
            "PUBLIX",
            "BANANAS 0.69",
        ]), storeHint: "Publix")

        XCTAssertNil(result.duplicateKey)
    }

    // MARK: - Empty input

    func test_emptyRows_returnsEmptyResult() {
        let result = ReceiptPreParser.parse(rows: [], storeHint: nil)
        XCTAssertTrue(result.candidateItems.isEmpty)
        XCTAssertNil(result.totalAmount)
        XCTAssertNil(result.duplicateKey)
    }

    // MARK: - Hints block

    func test_hintsBlock_nonEmpty_whenTotalsDetected() {
        let result = ReceiptPreParser.parse(rows: rows([
            "Subtotal|12.34",
            "Total|13.20",
        ]), storeHint: nil)

        XCTAssertFalse(result.hintsBlock.isEmpty)
        XCTAssertTrue(result.hintsBlock.contains("12.34"))
    }
}
