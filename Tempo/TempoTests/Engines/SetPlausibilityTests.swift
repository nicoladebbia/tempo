//
// SetPlausibilityTests.swift
// Tempo
//
// QA bug D — a 0 kg barbell row and a "300 × 1" typo were logged silently
// and fed e1RM / PRs / next week's load.
//

@testable import Tempo
import XCTest

final class SetPlausibilityTests: XCTestCase {
    func testZeroKgOnLoadedLiftAsks() {
        XCTAssertNotNil(SetPlausibility.warning(weightKg: 0, reps: 8, bestE1RMKg: nil, equipment: .barbell, isWarmup: false))
        XCTAssertNotNil(SetPlausibility.warning(weightKg: 0, reps: 8, bestE1RMKg: nil, equipment: .machine, isWarmup: true))
    }

    func testBodyweightAndBandNeverFlaggedForZero() {
        XCTAssertNil(SetPlausibility.warning(weightKg: 0, reps: 8, bestE1RMKg: 100, equipment: .pullUpBar, isWarmup: false))
        XCTAssertNil(SetPlausibility.warning(weightKg: 0, reps: 15, bestE1RMKg: nil, equipment: .resistanceBand, isWarmup: false))
    }

    func testFarBeyondBestAsks() {
        // best e1RM 100 → 300 × 1 is a typo.
        XCTAssertNotNil(SetPlausibility.warning(weightKg: 300, reps: 1, bestE1RMKg: 100, equipment: .barbell, isWarmup: false))
    }

    func testNormalProgressPasses() {
        // 85 × 5 ≈ 99 e1RM vs best 100 — a normal set.
        XCTAssertNil(SetPlausibility.warning(weightKg: 85, reps: 5, bestE1RMKg: 100, equipment: .barbell, isWarmup: false))
        // A solid PR (+10%) still passes without nagging.
        XCTAssertNil(SetPlausibility.warning(weightKg: 95, reps: 5, bestE1RMKg: 100, equipment: .barbell, isWarmup: false))
    }

    func testHighRepSetIsNotAFalseOutlier() {
        // 60 × 30 would be Epley 120; capped at 12 reps it's 84 → fine.
        XCTAssertNil(SetPlausibility.warning(weightKg: 60, reps: 30, bestE1RMKg: 100, equipment: .barbell, isWarmup: false))
    }

    func testNoHistoryNeverFlagsWeight() {
        XCTAssertNil(SetPlausibility.warning(weightKg: 140, reps: 3, bestE1RMKg: nil, equipment: .barbell, isWarmup: false))
    }
}
