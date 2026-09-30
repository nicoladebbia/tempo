//
// ReceiptMultiPhotoStitcherTests.swift
// Tempo
//
// Covers ReceiptMultiPhotoStitcher's seam-dedup logic (Round 2 item 4,
// multi-photo capture): a single page passes through unchanged, an
// overlapping tail/head pair between two pages is deduped to one copy, and
// two genuinely different rows that merely read similarly are both kept
// when they fall outside the seam window.
//

@testable import Tempo
import XCTest

final class ReceiptMultiPhotoStitcherTests: XCTestCase {
    private func page(_ lines: [String], confidence: Double = 0.95) -> ReceiptMultiPhotoStitcher.PageOCR {
        var y = 1.0
        let rows = lines.map { line -> VisionReceiptOCRResult.Row in
            defer { y -= 0.01 }
            return VisionReceiptOCRResult.Row(columns: line.components(separatedBy: "|"), yPosition: y, confidence: confidence)
        }
        return ReceiptMultiPhotoStitcher.PageOCR(rows: rows, averageConfidence: confidence)
    }

    func test_singlePage_passesThroughUnchanged() {
        let result = ReceiptMultiPhotoStitcher.stitch([page(["PUBLIX", "BANANAS|0.69"])])
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.averageConfidence, 0.95, accuracy: 0.001)
    }

    func test_overlappingSeam_dedupesRepeatedTailRows() {
        // Photo 1 ends with 3 real rows; photo 2 starts by re-capturing the
        // last 2 of those (the user was told to overlap shots slightly) then
        // continues with genuinely new content.
        let page1 = page(["MILK|2.99", "EGGS|3.49", "BREAD|2.19"])
        let page2 = page(["EGGS|3.49", "BREAD|2.19", "BUTTER|4.29", "CHEESE|5.99"])

        let result = ReceiptMultiPhotoStitcher.stitch([page1, page2])

        // The 2 overlapping rows from page2's head must be dropped, keeping
        // exactly the 5 distinct physical lines across both photos (each
        // row's `.text` joins its columns with a wide gap, not the `|` the
        // `page()` helper above uses to build columns).
        XCTAssertEqual(
            result.rows.map { $0.columns.joined(separator: "|") },
            ["MILK|2.99", "EGGS|3.49", "BREAD|2.19", "BUTTER|4.29", "CHEESE|5.99"]
        )
    }

    func test_noOverlap_keepsAllRowsFromBothPages() {
        let page1 = page(["MILK|2.99", "EGGS|3.49"])
        let page2 = page(["BUTTER|4.29", "CHEESE|5.99"])

        let result = ReceiptMultiPhotoStitcher.stitch([page1, page2])

        XCTAssertEqual(result.rows.count, 4)
    }

    func test_similarRowsBeyondSeamWindow_areBothKept_notCollapsed() {
        // Two distinct "SAVINGS" lines separated by more than `seamWindow`
        // (10) rows on page 2 must NOT be treated as a seam duplicate of
        // page 1's tail — only the head of page 2 is ever compared.
        let page1 = page(["ITEM A|1.00"])
        var page2Lines = ["SAVINGS TOTAL|0.50"]
        for i in 0 ..< 15 {
            page2Lines.append("FILLER \(i)|0.10")
        }
        page2Lines.append("SAVINGS TOTAL|0.50")
        let page2 = page(page2Lines)

        let result = ReceiptMultiPhotoStitcher.stitch([page1, page2])

        // Both "SAVINGS TOTAL" rows on page 2 should survive — the second
        // one is far past the seam window, so it's new content, not a
        // duplicate of the first.
        let savingsCount = result.rows.filter { $0.text.hasPrefix("SAVINGS TOTAL") }.count
        XCTAssertEqual(savingsCount, 2)
    }

    func test_emptyPages_returnsEmptyResult() {
        let result = ReceiptMultiPhotoStitcher.stitch([])
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.averageConfidence, 0)
    }
}
