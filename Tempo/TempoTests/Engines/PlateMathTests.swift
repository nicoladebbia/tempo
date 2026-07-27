//
// PlateMathTests.swift
// Tempo
//
// §5 plate calculator — pins the greedy per-side breakdown. Greedy is exact
// for the standard set (each denomination ≥ sum of all smaller), so these
// also document that invariant.
//

@testable import Tempo
import XCTest

final class PlateMathTests: XCTestCase {
    func testExactBreakdownLargestFirst() {
        // 100 kg bar total on a 20 kg bar → 40 kg/side → 25 + 15.
        XCTAssertEqual(PlateMath.breakdown(perSideKg: 40), [25, 15])
        XCTAssertEqual(PlateMath.breakdown(perSideKg: 22.5), [20, 2.5])
        XCTAssertEqual(PlateMath.breakdown(perSideKg: 1.25), [1.25])
    }

    func testSubPlateRemainderIsDroppedAndFlaggedInexact() {
        // 22.6 → 20 + 2.5, with 0.1 unreachable (smallest plate 1.25).
        let plates = PlateMath.breakdown(perSideKg: 22.6)
        XCTAssertEqual(plates, [20, 2.5])
        XCTAssertFalse(PlateMath.isExact(plates: plates, perSideKg: 22.6))
        XCTAssertTrue(PlateMath.isExact(plates: plates, perSideKg: 22.5))
    }

    func testZeroAndTinyTargets() {
        XCTAssertTrue(PlateMath.breakdown(perSideKg: 0).isEmpty)
        XCTAssertTrue(PlateMath.breakdown(perSideKg: 1.0).isEmpty,
                      "Below the smallest plate nothing fits")
    }

    func testFloatingPointBoundaryLandsThePlate() {
        // 3 × 2.5 accumulated as doubles must still yield three 2.5s, not two —
        // the 1 g tolerance in breakdown() absorbs FP drift.
        XCTAssertEqual(PlateMath.breakdown(perSideKg: 7.5), [5, 2.5])
        XCTAssertEqual(PlateMath.breakdown(perSideKg: 2.5 + 2.5 + 2.5 - 5), [2.5])
    }

    func testKgLabel() {
        XCTAssertEqual(PlateMath.label(plates: [20, 2.5], in: .kg), "20 + 2.5")
        XCTAssertEqual(PlateMath.label(plates: [], in: .kg), "")
    }
}
