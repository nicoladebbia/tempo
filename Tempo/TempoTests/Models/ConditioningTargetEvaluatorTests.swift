//
// ConditioningTargetEvaluatorTests.swift
// Tempo
//
// Fix #7 — the target-met rule for each parsed conditioning shape: every rep
// under the cap, duration within the tolerant lower bound, rounds ≥ the
// prescribed sets × reps, distance within GPS-noise tolerance. Freeform (or
// missing data) is always "unknown", never a false ✓/✗.
//

@testable import Tempo
import XCTest

final class ConditioningTargetEvaluatorTests: XCTestCase {
    private func target(_ kind: ConditioningTargetKind) -> ConditioningTarget {
        ConditioningTarget(kind: kind, rawText: "test")
    }

    // MARK: - repsDistance

    func testRepsDistanceMetWhenEveryRepUnderCap() {
        let t = target(.repsDistance(reps: 4, distance: 25, unit: .yards, capSeconds: 65))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: [60, 62, 64, 58], durationSeconds: nil, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertEqual(met, true)
    }

    func testRepsDistanceNotMetWhenOneRepOverCap() {
        let t = target(.repsDistance(reps: 4, distance: 25, unit: .yards, capSeconds: 65))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: [60, 66, 64, 58], durationSeconds: nil, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertEqual(met, false)
    }

    func testRepsDistanceExactlyOnCapCounts() {
        let t = target(.repsDistance(reps: 1, distance: 25, unit: .yards, capSeconds: 65))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: [65], durationSeconds: nil, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertEqual(met, true, "≤ cap, not < cap")
    }

    func testRepsDistanceUnknownWithNoCap() {
        let t = target(.repsDistance(reps: 4, distance: 25, unit: .yards, capSeconds: nil))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: [60, 62], durationSeconds: nil, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertNil(met)
    }

    func testRepsDistanceUnknownWithNoLoggedTimes() {
        let t = target(.repsDistance(reps: 4, distance: 25, unit: .yards, capSeconds: 65))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: nil, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertNil(met)
    }

    func testRepsDistanceUnknownWithEmptyLoggedTimes() {
        let t = target(.repsDistance(reps: 4, distance: 25, unit: .yards, capSeconds: 65))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: [], durationSeconds: nil, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertNil(met)
    }

    // MARK: - duration

    func testDurationMetAtExactTarget() {
        let t = target(.duration(minutes: 35))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: 35 * 60, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertEqual(met, true)
    }

    func testDurationMetWithinTenPercentTolerance() {
        let t = target(.duration(minutes: 35))
        // 32 minutes = ~91.4% of 35 — inside the -10% floor.
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: 32 * 60, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertEqual(met, true)
    }

    func testDurationNotMetWhenCutShort() {
        let t = target(.duration(minutes: 35))
        // 20 minutes is well under 90% of target.
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: 20 * 60, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertEqual(met, false)
    }

    func testDurationMetWhenExceedingTarget() {
        let t = target(.duration(minutes: 15))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: 25 * 60, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertEqual(met, true, "going long is never a miss")
    }

    func testDurationUnknownWithNoLoggedDuration() {
        let t = target(.duration(minutes: 35))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: nil, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertNil(met)
    }

    // MARK: - intervalSets

    func testIntervalSetsMetWhenRoundsMeetTarget() {
        let t = target(.intervalSets(sets: 2, reps: 10))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: nil, distanceMeters: nil, roundsCompleted: 20
        )
        XCTAssertEqual(met, true)
    }

    func testIntervalSetsNotMetWhenRoundsShort() {
        let t = target(.intervalSets(sets: 2, reps: 10))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: nil, distanceMeters: nil, roundsCompleted: 14
        )
        XCTAssertEqual(met, false)
    }

    func testIntervalSetsUnknownWithNoRoundsLogged() {
        let t = target(.intervalSets(sets: 2, reps: 10))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: nil, distanceMeters: nil, roundsCompleted: nil
        )
        XCTAssertNil(met)
    }

    // MARK: - distance

    func testDistanceMetAtExactTarget() {
        let t = target(.distance(value: 5, unit: .kilometers))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: nil, distanceMeters: 5000, roundsCompleted: nil
        )
        XCTAssertEqual(met, true)
    }

    func testDistanceMetWithinGPSTolerance() {
        let t = target(.distance(value: 5, unit: .kilometers))
        // 4.9km is inside the 3% tolerance (4850m floor).
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: nil, distanceMeters: 4900, roundsCompleted: nil
        )
        XCTAssertEqual(met, true)
    }

    func testDistanceNotMetWhenShort() {
        let t = target(.distance(value: 5, unit: .kilometers))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: nil, distanceMeters: 3000, roundsCompleted: nil
        )
        XCTAssertEqual(met, false)
    }

    func testDistanceUnitConversionYards() {
        let t = target(.distance(value: 300, unit: .yards))
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: nil, durationSeconds: nil, distanceMeters: 274.32, roundsCompleted: nil
        )
        XCTAssertEqual(met, true, "300y == 274.32m")
    }

    // MARK: - freeform

    func testFreeformIsAlwaysUnknown() {
        let t = target(.freeform)
        let met = ConditioningTargetEvaluator.targetMet(
            target: t, repTimesSeconds: [60], durationSeconds: 100, distanceMeters: 1000, roundsCompleted: 5
        )
        XCTAssertNil(met, "freeform never claims a ✓/✗")
    }

    // MARK: - bestTime

    func testBestTimePicksTheMinimum() {
        XCTAssertEqual(ConditioningTargetEvaluator.bestTime([62, 58, 60]), 58)
    }

    func testBestTimeNilForEmptyOrNil() {
        XCTAssertNil(ConditioningTargetEvaluator.bestTime([]))
        XCTAssertNil(ConditioningTargetEvaluator.bestTime(nil))
    }
}
