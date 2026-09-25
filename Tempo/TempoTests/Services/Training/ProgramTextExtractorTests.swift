//
// ProgramTextExtractorTests.swift
// Tempo
//
// Pins the pure, Vision-free part of trainer-program OCR: ordering hand-built
// bounding-box observations into reading order (top row to bottom row, left
// to right within a row) — the part that matters for a table-style sets/reps
// sheet, and the only part that can be unit-tested without a real Vision call.
//
// Also pins `positionAwareLines(on:)`'s own glue — mapping PDFKit's
// per-line selection bounds into `order()`'s normalized-bounding-box
// contract (bottom-left origin, 0-1 range) — against small synthetic PDFs
// built with UIGraphicsPDFRenderer. PDFKit's own line-grouping heuristic
// (which real trainer-sheet content ends up on the same "line") is a
// platform behavior these tests don't try to pin; that contract was instead
// verified against two real trainer PDFs during development (see the PR
// description) — this file only pins that OUR normalization math and
// ordering are correct once PDFKit hands back its line selections.
//

import PDFKit
@testable import Tempo
import UIKit
import XCTest

final class ProgramTextExtractorTests: XCTestCase {
    private typealias Observation = ProgramTextExtractor.TextObservation

    /// Vision's box: origin bottom-left, normalized 0-1. `y` near 1 = near
    /// the top of the image.
    private func box(x: CGFloat, y: CGFloat, width: CGFloat = 0.1, height: CGFloat = 0.03) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    func testOrdersTopToBottom() {
        let observations = [
            Observation(text: "Bottom line", boundingBox: box(x: 0.1, y: 0.1)),
            Observation(text: "Top line", boundingBox: box(x: 0.1, y: 0.9)),
            Observation(text: "Middle line", boundingBox: box(x: 0.1, y: 0.5)),
        ]
        XCTAssertEqual(
            ProgramTextExtractor.order(observations),
            ["Top line", "Middle line", "Bottom line"]
        )
    }

    func testOrdersColumnsLeftToRightWithinARow() {
        // A "3 x 10" table row split into 3 separate observations at the
        // same vertical position — exactly what Vision hands back for a
        // sets/reps table.
        let observations = [
            Observation(text: "10", boundingBox: box(x: 0.6, y: 0.5)),
            Observation(text: "Bench Press", boundingBox: box(x: 0.1, y: 0.5)),
            Observation(text: "3", boundingBox: box(x: 0.4, y: 0.5)),
        ]
        let ordered = ProgramTextExtractor.order(observations)
        XCTAssertEqual(ordered.count, 1, "same-row observations collapse into one line")
        XCTAssertEqual(ordered.first, "Bench Press   3   10")
    }

    func testRowClusteringToleratesSmallBaselineJitter() {
        // Two observations 0.01 apart vertically (within tolerance) still
        // count as the same printed row.
        let observations = [
            Observation(text: "Squat", boundingBox: box(x: 0.1, y: 0.500)),
            Observation(text: "5x5", boundingBox: box(x: 0.5, y: 0.508)),
        ]
        let ordered = ProgramTextExtractor.order(observations, rowTolerance: 0.015)
        XCTAssertEqual(ordered, ["Squat   5x5"])
    }

    func testRowClusteringSplitsRowsBeyondTolerance() {
        let observations = [
            Observation(text: "Week 1", boundingBox: box(x: 0.1, y: 0.9)),
            Observation(text: "Week 2", boundingBox: box(x: 0.1, y: 0.5)),
        ]
        let ordered = ProgramTextExtractor.order(observations, rowTolerance: 0.015)
        XCTAssertEqual(ordered, ["Week 1", "Week 2"])
    }

    func testEmptyInputProducesNoLines() {
        XCTAssertEqual(ProgramTextExtractor.order([]), [])
    }

    func testMultiRowTableOrdersAsWholeDocument() {
        let observations = [
            Observation(text: "Reps", boundingBox: box(x: 0.6, y: 0.9)),
            Observation(text: "Exercise", boundingBox: box(x: 0.1, y: 0.9)),
            Observation(text: "10", boundingBox: box(x: 0.6, y: 0.7)),
            Observation(text: "Bench", boundingBox: box(x: 0.1, y: 0.7)),
            Observation(text: "8", boundingBox: box(x: 0.6, y: 0.5)),
            Observation(text: "Squat", boundingBox: box(x: 0.1, y: 0.5)),
        ]
        XCTAssertEqual(
            ProgramTextExtractor.order(observations),
            ["Exercise   Reps", "Bench   10", "Squat   8"]
        )
    }

    // MARK: - Position-aware PDF text

    /// Builds a one-page PDF with each string drawn at its own rect (UIKit
    /// coordinates: origin top-left, y down — matching how `NSString.draw
    /// (in:)` is used everywhere else in this file's production code).
    private func makeSyntheticPDFPage(lines: [(text: String, rect: CGRect)], pageSize: CGSize) -> PDFPage {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let data = renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14)]
            for line in lines {
                (line.text as NSString).draw(in: line.rect, withAttributes: attributes)
            }
        }
        guard let page = PDFDocument(data: data)?.page(at: 0) else {
            fatalError("synthetic PDF failed to build — test setup is broken")
        }
        return page
    }

    func testPositionAwareLinesOrdersDistinctRowsTopToBottom() {
        let pageSize = CGSize(width: 300, height: 200)
        // UIKit y increases downward, so the smallest y is visually topmost.
        let page = makeSyntheticPDFPage(
            lines: [
                (text: "Row 3", rect: CGRect(x: 20, y: 140, width: 200, height: 20)),
                (text: "Row 1", rect: CGRect(x: 20, y: 20, width: 200, height: 20)),
                (text: "Row 2", rect: CGRect(x: 20, y: 80, width: 200, height: 20)),
            ],
            pageSize: pageSize
        )
        XCTAssertEqual(
            ProgramTextExtractor.positionAwareLines(on: page),
            ["Row 1", "Row 2", "Row 3"]
        )
    }

    func testPositionAwareTextJoinsLinesWithNewlines() throws {
        let pageSize = CGSize(width: 300, height: 200)
        let page = makeSyntheticPDFPage(
            lines: [
                (text: "Section Title", rect: CGRect(x: 20, y: 20, width: 200, height: 20)),
                (text: "A Squat 3x5", rect: CGRect(x: 20, y: 80, width: 200, height: 20)),
            ],
            pageSize: pageSize
        )
        let text = try XCTUnwrap(ProgramTextExtractor.positionAwareText(on: page))
        XCTAssertEqual(text, "Section Title\nA Squat 3x5")
    }

    func testPositionAwareTextIsNilForABlankPage() {
        let page = makeSyntheticPDFPage(lines: [], pageSize: CGSize(width: 300, height: 200))
        XCTAssertNil(ProgramTextExtractor.positionAwareText(on: page))
        XCTAssertEqual(ProgramTextExtractor.positionAwareLines(on: page), [])
    }
}
