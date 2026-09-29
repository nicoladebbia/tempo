//
// VisionReceiptOCRRowReconstructionTests.swift
// Tempo
//
// Covers VisionReceiptOCR.reconstructRows in isolation from Vision itself —
// it takes plain (text, confidence, box) tuples, so row/column grouping
// logic (the fix for the "item name and price scrambled because they're
// separate Vision observations joined in raw array order" bug) is fully
// unit-testable without a real image or the Vision framework. Coordinates
// use Vision's convention: normalized 0...1, origin bottom-left, so a
// LARGER y is HIGHER on the page (earlier in reading order).
//

@testable import Tempo
import XCTest

final class VisionReceiptOCRRowReconstructionTests: XCTestCase {
    private typealias Observation = (text: String, confidence: Double, box: CGRect)

    private func obs(_ text: String, x: Double, y: Double, confidence: Double = 0.95) -> Observation {
        (text: text, confidence: confidence, box: CGRect(x: x, y: y, width: 0.1, height: 0.02))
    }

    func test_emptyInput_returnsEmptyRows() {
        XCTAssertTrue(VisionReceiptOCR.reconstructRows([]).isEmpty)
    }

    func test_singleRow_twoColumns_orderedLeftToRight() {
        // Price observation comes FIRST in the raw array (as Vision might
        // return them out of reading order) but must still end up AFTER the
        // item name in the reconstructed row, since it's further right (x).
        let observations = [
            obs("0.69", x: 0.7, y: 0.5),
            obs("BANANAS", x: 0.1, y: 0.5),
        ]
        let rows = VisionReceiptOCR.reconstructRows(observations)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].columns, ["BANANAS", "0.69"])
    }

    func test_multipleRows_orderedTopToBottom() {
        let observations = [
            obs("BANANAS", x: 0.1, y: 0.5),
            obs("0.69", x: 0.7, y: 0.5),
            obs("MILK", x: 0.1, y: 0.7), // higher y = higher on page = earlier
            obs("2.99", x: 0.7, y: 0.7),
        ]
        let rows = VisionReceiptOCR.reconstructRows(observations)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].columns, ["MILK", "2.99"])
        XCTAssertEqual(rows[1].columns, ["BANANAS", "0.69"])
    }

    func test_closeYValues_clusterIntoSameRow() {
        // Real Vision observations on the same printed line are rarely at
        // EXACTLY the same y — a small jitter (e.g. italic price vs. name
        // baseline) must still cluster into one row.
        let observations = [
            obs("EGGS", x: 0.1, y: 0.500),
            obs("3.49", x: 0.7, y: 0.503),
        ]
        let rows = VisionReceiptOCR.reconstructRows(observations)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].columns, ["EGGS", "3.49"])
    }

    func test_farYValues_dontCluster_evenWithFewRows() {
        // Adaptive threshold falls back to 0.006 default when there's only
        // one gap to measure from — two rows a full 0.1 apart must never
        // merge regardless of that fallback.
        let observations = [
            obs("EGGS", x: 0.1, y: 0.9),
            obs("MILK", x: 0.1, y: 0.5),
        ]
        let rows = VisionReceiptOCR.reconstructRows(observations)
        XCTAssertEqual(rows.count, 2)
    }

    func test_rowText_joinsColumnsWithWideGap() {
        let observations = [
            obs("BANANAS", x: 0.1, y: 0.5),
            obs("0.69", x: 0.7, y: 0.5),
        ]
        let rows = VisionReceiptOCR.reconstructRows(observations)
        XCTAssertEqual(rows[0].text, "BANANAS    0.69")
    }

    func test_threeColumnRow_allOrderedByX() {
        let observations = [
            obs("F", x: 0.9, y: 0.5),
            obs("GREEK YOGURT", x: 0.1, y: 0.5),
            obs("4.99", x: 0.6, y: 0.5),
        ]
        let rows = VisionReceiptOCR.reconstructRows(observations)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].columns, ["GREEK YOGURT", "4.99", "F"])
    }
}
