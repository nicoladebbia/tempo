//
// PlateMathTests.swift
// Tempo
//
// §5 plate calculator — pins the greedy per-side breakdown. Greedy is exact
// for the standard set (each denomination ≥ sum of all smaller), so these
// also document that invariant. Unit-agnostic math: kg targets break against
// kg denominations, lbs targets against the US plate set — never converted.
//

@testable import Tempo
import XCTest

final class PlateMathTests: XCTestCase {
    func testExactBreakdownLargestFirst() {
        // 100 kg bar total on a 20 kg bar → 40 kg/side → 25 + 15.
        XCTAssertEqual(PlateMath.breakdown(perSide: 40), [25, 15])
        XCTAssertEqual(PlateMath.breakdown(perSide: 22.5), [20, 2.5])
        XCTAssertEqual(PlateMath.breakdown(perSide: 1.25), [1.25])
    }

    func testLbsBreakdownUsesUSDenominations() {
        // 90 lbs total on a 45 lb bar → 22.5 lbs/side → 10 + 10 + 2.5.
        let lbs = PlateMath.plates(for: .lbs)
        XCTAssertEqual(PlateMath.breakdown(perSide: 22.5, plates: lbs), [10, 10, 2.5])
        // 135 total → 45/side → one 45 plate.
        XCTAssertEqual(PlateMath.breakdown(perSide: 45, plates: lbs), [45])
        XCTAssertTrue(PlateMath.isExact(plates: [10, 10, 2.5], perSide: 22.5))
    }

    func testSubPlateRemainderIsDroppedAndFlaggedInexact() {
        // 22.6 → 20 + 2.5, with 0.1 unreachable (smallest plate 1.25).
        let plates = PlateMath.breakdown(perSide: 22.6)
        XCTAssertEqual(plates, [20, 2.5])
        XCTAssertFalse(PlateMath.isExact(plates: plates, perSide: 22.6))
        XCTAssertTrue(PlateMath.isExact(plates: plates, perSide: 22.5))
    }

    func testZeroAndTinyTargets() {
        XCTAssertTrue(PlateMath.breakdown(perSide: 0).isEmpty)
        XCTAssertTrue(PlateMath.breakdown(perSide: 1.0).isEmpty,
                      "Below the smallest plate nothing fits")
    }

    func testFloatingPointBoundaryLandsThePlate() {
        // 3 × 2.5 accumulated as doubles must still yield three 2.5s, not two —
        // the 1 g tolerance in breakdown() absorbs FP drift.
        XCTAssertEqual(PlateMath.breakdown(perSide: 7.5), [5, 2.5])
        XCTAssertEqual(PlateMath.breakdown(perSide: 2.5 + 2.5 + 2.5 - 5), [2.5])
    }

    func testLabel() {
        XCTAssertEqual(PlateMath.label(values: [20, 2.5]), "20 + 2.5")
        XCTAssertEqual(PlateMath.label(values: [45, 2.5]), "45 + 2.5")
        XCTAssertEqual(PlateMath.label(values: []), "")
    }
}
