//
// AdaptiveProfileUpdaterTests.swift
// Tempo
//
// Phase 3 (TRAINING_INTELLIGENCE_TO_10.md Fix 3.5) — the learning rule.
// Proves the on-device personalization is BOUNDED (never runs away), that the
// clamps hold, that it CONVERGES, and — the property that defines a 9 — that
// two users with different RPE histories end up with different prescriptions.
// AdaptiveProfileUpdater.ingest is pure, so no device / network / store.
//

@testable import Tempo
import XCTest

final class AdaptiveProfileUpdaterTests: XCTestCase {

    private let exID = UUID()

    private func history(avgRPE: Double?, form: FormQuality = .clean, sampleCount: Int = 3) -> ExerciseHistory {
        let ex = Exercise(
            name: "Bench Press",
            muscleGroup: .chest,
            equipment: .barbell,
            movementPattern: .horizontalPush,
            isCompound: true
        )
        ex.id = exID
        return ExerciseHistory(
            date: Date(),
            avgRPE: avgRPE,
            worstFormRaw: form.rawValue,
            feedbackSampleCount: sampleCount,
            exercise: ex
        )
    }

    private func ingest(_ rows: [ExerciseHistory], into profile: AdaptiveProfile) {
        AdaptiveProfileUpdater.ingest(
            session: rows,
            baseIncrement: { _ in 2.5 }, // barbell default
            into: profile
        )
    }

    // MARK: - Direction

    func testEasySessionRaisesIncrement() {
        let p = AdaptiveProfile()
        ingest([history(avgRPE: 5)], into: p)
        XCTAssertGreaterThan(p.learnedIncrements[exID]!, 2.5, "Easy clean session should raise the learned step")
    }

    func testHardSessionLowersIncrement() {
        let p = AdaptiveProfile()
        ingest([history(avgRPE: 9)], into: p)
        XCTAssertLessThan(p.learnedIncrements[exID]!, 2.5, "Hard session should lower the learned step")
    }

    func testBrokenFormLowersIncrement() {
        let p = AdaptiveProfile()
        ingest([history(avgRPE: 7, form: .failed)], into: p)
        XCTAssertLessThan(p.learnedIncrements[exID]!, 2.5, "Form breakdown should lower the step even at mid RPE")
    }

    func testMiddleBandLeavesIncrementUnchanged() {
        let p = AdaptiveProfile()
        ingest([history(avgRPE: 7.5)], into: p)
        // No learned value written when the increment is well-matched.
        XCTAssertNil(p.learnedIncrements[exID], "Mid-RPE clean session shouldn't move a well-matched step")
    }

    func testNoSignalLeavesProfileUntouched() {
        let p = AdaptiveProfile()
        ingest([history(avgRPE: nil, sampleCount: 0)], into: p)
        XCTAssertTrue(p.learnedIncrements.isEmpty)
        XCTAssertNil(p.fatigueEWMA)
        XCTAssertEqual(p.recoveryThresholdOffset, 0)
    }

    // MARK: - Bounds (no runaway)

    func testIncrementNeverExceedsCeilingUnderRepeatedEasy() {
        let p = AdaptiveProfile()
        for _ in 0 ..< 50 { ingest([history(avgRPE: 4)], into: p) }
        XCTAssertLessThanOrEqual(p.learnedIncrements[exID]!, AdaptiveProfileUpdater.maxIncrement)
    }

    func testIncrementNeverDropsBelowFloorUnderRepeatedHard() {
        let p = AdaptiveProfile()
        for _ in 0 ..< 50 { ingest([history(avgRPE: 10)], into: p) }
        XCTAssertGreaterThanOrEqual(p.learnedIncrements[exID]!, AdaptiveProfileUpdater.minIncrement)
    }

    func testThresholdOffsetClampsAtPlusMinus10() {
        let pHard = AdaptiveProfile()
        for _ in 0 ..< 100 { ingest([history(avgRPE: 10)], into: pHard) }
        XCTAssertLessThanOrEqual(pHard.recoveryThresholdOffset, AdaptiveProfile.maxThresholdOffset)

        let pEasy = AdaptiveProfile()
        for _ in 0 ..< 100 { ingest([history(avgRPE: 4)], into: pEasy) }
        XCTAssertGreaterThanOrEqual(pEasy.recoveryThresholdOffset, AdaptiveProfile.minThresholdOffset)
    }

    // MARK: - Convergence

    func testConvergesToStableHigherIncrement() {
        // 8 easy sessions should raise the step to a stable higher value, not
        // oscillate or explode.
        let p = AdaptiveProfile()
        var prev = 2.5
        for i in 0 ..< 8 {
            ingest([history(avgRPE: 5)], into: p)
            let now = p.learnedIncrements[exID]!
            XCTAssertGreaterThanOrEqual(now, prev, "Monotonic non-decreasing under repeated easy (step \(i))")
            prev = now
        }
        XCTAssertGreaterThan(prev, 2.5)
        XCTAssertLessThanOrEqual(prev, AdaptiveProfileUpdater.maxIncrement)
    }

    // MARK: - Fatigue EWMA

    func testFatigueEWMAIsMonotonicUnderConstantHighRPE() {
        let p = AdaptiveProfile()
        ingest([history(avgRPE: 9)], into: p)
        let first = p.fatigueEWMA!
        ingest([history(avgRPE: 9)], into: p)
        let second = p.fatigueEWMA!
        // Constant high input → EWMA climbs toward it.
        XCTAssertGreaterThanOrEqual(second, first)
        XCTAssertLessThanOrEqual(second, 9.0)
    }

    // MARK: - The 9: personalization

    func testTwoHistoriesProduceDifferentLearnedIncrements() {
        // Same exercise, same starting point — but one user logs easy, the
        // other hard. Their learned increments must DIVERGE. This is the
        // definition of personalization.
        let easyUser = AdaptiveProfile()
        let hardUser = AdaptiveProfile()
        for _ in 0 ..< 5 {
            ingest([history(avgRPE: 5)], into: easyUser)
            ingest([history(avgRPE: 9)], into: hardUser)
        }
        XCTAssertNotEqual(
            easyUser.learnedIncrements[exID]!,
            hardUser.learnedIncrements[exID]!,
            "Different RPE histories must yield different prescriptions"
        )
        XCTAssertGreaterThan(easyUser.learnedIncrements[exID]!, hardUser.learnedIncrements[exID]!)
    }
}
