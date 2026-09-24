//
// ProgramTextExtractorTests.swift
// Tempo
//
// Pins the pure, Vision-free part of trainer-program OCR: ordering hand-built
// bounding-box observations into reading order (top row to bottom row, left
// to right within a row) — the part that matters for a table-style sets/reps
// sheet, and the only part that can be unit-tested without a real Vision call.
//

@testable import Tempo
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
}
