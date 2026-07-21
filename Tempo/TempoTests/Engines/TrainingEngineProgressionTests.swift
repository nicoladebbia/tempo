//
// TrainingEngineProgressionTests.swift
// Tempo
//
// Phase 1 (TRAINING_INTELLIGENCE_TO_10.md) — closed feedback loop.
// Covers the NEW ProgressionDecision contract (rationale + deltaApplied) and
// the conditioning-debt rest multiplier. The pre-existing veto rules live in
// ProgressiveOverloadFeedbackTests; this file asserts the sizing + breath path
// and pins determinism so the deterministic floor can never silently drift.
//

@testable import Tempo
import XCTest

final class TrainingEngineProgressionTests: XCTestCase {
    private var engine: TrainingEngine!

    override func setUp() {
        super.setUp()
        engine = TrainingEngine()
    }

    // MARK: - Fixtures

    private func compoundExercise() -> Exercise {
        Exercise(
            name: "Back Squat",
            muscleGroup: .quads,
            equipment: .barbell,
            movementPattern: .squat,
            isCompound: true
        )
    }

    private func history(
        daysAgo: Int,
        weight: Double,
        reps: Int,
        avgRPE: Double? = nil,
        worstForm: FormQuality? = nil,
        sampleCount: Int = 0,
        gassedFraction: Double? = nil
    ) -> ExerciseHistory {
        ExerciseHistory(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            bestSetWeight: weight,
            bestSetReps: reps,
            avgRPE: avgRPE,
            worstFormRaw: worstForm?.rawValue,
            feedbackSampleCount: sampleCount,
            gassedFraction: gassedFraction
        )
    }

    // MARK: - Rationale paths

    @MainActor
    func testAcceleratedEasyLoad() {
        let ex = compoundExercise()
        let hist = [
            history(daysAgo: 2, weight: 100, reps: 8, avgRPE: 5, worstForm: .clean, sampleCount: 3),
            history(daysAgo: 5, weight: 100, reps: 8, avgRPE: 5, worstForm: .clean, sampleCount: 3),
        ]
        let d = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(d.rationale, .acceleratedEasyLoad)
        XCTAssertEqual(d.deltaApplied, 5.0, accuracy: 0.01, "Easy clean session → double barbell increment")
        XCTAssertEqual(d.weight, 105.0, accuracy: 0.01)
    }

    @MainActor
    func testStandardProgression() {
        let ex = compoundExercise()
        let hist = [
            history(daysAgo: 2, weight: 100, reps: 8, avgRPE: 8, worstForm: .clean, sampleCount: 3),
            history(daysAgo: 5, weight: 100, reps: 8, avgRPE: 8, worstForm: .clean, sampleCount: 3),
        ]
        let d = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(d.rationale, .standardProgression)
        XCTAssertEqual(d.deltaApplied, 2.5, accuracy: 0.01, "Normal RPE → single increment")
    }

    @MainActor
    func testHeldHighRPE() {
        let ex = compoundExercise()
        let hist = [
            history(daysAgo: 2, weight: 100, reps: 8, avgRPE: 9, worstForm: .clean, sampleCount: 3),
            history(daysAgo: 5, weight: 100, reps: 8, avgRPE: 8, worstForm: .clean, sampleCount: 3),
        ]
        let d = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(d.rationale, .heldHighRPE)
        XCTAssertEqual(d.deltaApplied, 0, accuracy: 0.01)
        XCTAssertEqual(d.weight, 100, accuracy: 0.01)
    }

    @MainActor
    func testHeldBrokenForm() {
        let ex = compoundExercise()
        let hist = [
            history(daysAgo: 2, weight: 100, reps: 8, avgRPE: 7, worstForm: .failed, sampleCount: 3),
            history(daysAgo: 5, weight: 100, reps: 8, avgRPE: 7, worstForm: .clean, sampleCount: 3),
        ]
        let d = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(d.rationale, .heldBrokenForm)
        XCTAssertEqual(d.deltaApplied, 0, accuracy: 0.01)
    }

    @MainActor
    func testHeldInsufficientData() {
        let ex = compoundExercise()
        let hist = [history(daysAgo: 2, weight: 100, reps: 8)]
        let d = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(d.rationale, .heldInsufficientData)
        XCTAssertEqual(d.weight, 100, accuracy: 0.01, "One session → hold at last known weight")
    }

    @MainActor
    func testDeloadedRepeatedFailure() {
        let ex = compoundExercise()
        // Three sessions well below target (8 reps target, hitting ~5) → step down.
        let hist = [
            history(daysAgo: 2, weight: 100, reps: 5),
            history(daysAgo: 5, weight: 100, reps: 5),
            history(daysAgo: 8, weight: 100, reps: 5),
        ]
        let d = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(d.rationale, .deloadedRepeatedFailure)
        XCTAssertEqual(d.deltaApplied, -2.5, accuracy: 0.01)
        XCTAssertEqual(d.weight, 97.5, accuracy: 0.01)
    }

    // MARK: - e1RM re-anchor (weight/reps decoupling fix)

    /// Build a history row carrying a stored e1RM (as real completion rows do —
    /// the unit fixtures above omit it, which is why they keep pre-e1RM behavior).
    private func e1RMHistory(daysAgo: Int, e1RM: Double, weight: Double, reps: Int) -> ExerciseHistory {
        ExerciseHistory(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            estimated1RM: e1RM,
            bestSetWeight: weight,
            bestSetReps: reps
        )
    }

    @MainActor
    func testE1RMAnchorDerivesTargetRepWeightFromMismatchedReps() {
        let ex = compoundExercise() // barbell squat, target 8 reps
        // Heavy triples: 100 kg × 3, e1RM stored (Epley = 110). The old engine
        // anchored the 8-rep target at 100 kg (a weight only good for 3). The
        // re-anchor derives the 8-rep equivalent instead.
        let e1RM = 100.0 * (1 + 3.0 / 30.0) // 110
        let hist = [
            e1RMHistory(daysAgo: 2, e1RM: e1RM, weight: 100, reps: 3),
            e1RMHistory(daysAgo: 5, e1RM: e1RM, weight: 100, reps: 3),
        ]
        let d = engine.calculateProgressiveOverload(for: ex, history: hist)
        let expected = e1RM / (1 + 8.0 / 30.0) // ~86.8
        XCTAssertEqual(d.weight, expected, accuracy: 0.1, "8-rep weight derived from e1RM, not the 3-rep load")
        XCTAssertLessThan(d.weight, 100, "Must prescribe below the weight ground out for 3 reps")
    }

    @MainActor
    func testE1RMAnchorRoundTripsWhenRepsMatchTarget() {
        let ex = compoundExercise()
        // 100 kg × 8 (reps == target) with e1RM stored → anchor round-trips to
        // exactly 100, so a standard progression still lands on 102.5 (no drift).
        let e1RM = 100.0 * (1 + 8.0 / 30.0)
        let hist = [
            e1RMHistory(daysAgo: 2, e1RM: e1RM, weight: 100, reps: 8),
            e1RMHistory(daysAgo: 5, e1RM: e1RM, weight: 100, reps: 8),
        ]
        let d = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(d.weight, 102.5, accuracy: 0.01, "Rep-matched e1RM anchor round-trips → standard +2.5")
    }

    // MARK: - Conditioning debt (rest multiplier)

    func testRestMultiplierBaselineWhenNotGassed() {
        let hist = [
            history(daysAgo: 2, weight: 100, reps: 8, gassedFraction: 0.0),
            history(daysAgo: 5, weight: 100, reps: 8, gassedFraction: 0.2),
        ]
        XCTAssertEqual(engine.restMultiplier(history: hist), 1.0, accuracy: 0.01)
    }

    func testRestMultiplierRaisedUnderConditioningDebt() {
        // Two of the last three sessions were >= 50% gassed → +25% rest.
        let hist = [
            history(daysAgo: 2, weight: 100, reps: 8, gassedFraction: 0.6),
            history(daysAgo: 5, weight: 100, reps: 8, gassedFraction: 0.5),
            history(daysAgo: 8, weight: 100, reps: 8, gassedFraction: 0.0),
        ]
        XCTAssertEqual(engine.restMultiplier(history: hist), 1.25, accuracy: 0.01)
    }

    func testRestMultiplierIgnoresNilGassedFraction() {
        // No breath signal anywhere → baseline, never inflated.
        let hist = [
            history(daysAgo: 2, weight: 100, reps: 8, gassedFraction: nil),
            history(daysAgo: 5, weight: 100, reps: 8, gassedFraction: nil),
        ]
        XCTAssertEqual(engine.restMultiplier(history: hist), 1.0, accuracy: 0.01)
    }

    // MARK: - Fatigue-triggered deload (Phase 3 Fix 3.4)

    func testFatigueTriggersEarlyDeload() {
        // Not on a periodic deload week, but a high fatigue trend forces one.
        let start = Calendar.current.date(byAdding: .weekOfYear, value: -2, to: Date())!
        let deload = engine.isDeloadWeek(
            date: Date(), deloadFrequencyWeeks: 5, trainingStartDate: start, fatigueEWMA: 9.0
        )
        XCTAssertTrue(deload, "High fatigue EWMA should trigger an early deload off-cycle")
    }

    func testNoFatigueNoEarlyDeloadOffCycle() {
        let start = Calendar.current.date(byAdding: .weekOfYear, value: -2, to: Date())!
        let deload = engine.isDeloadWeek(
            date: Date(), deloadFrequencyWeeks: 5, trainingStartDate: start, fatigueEWMA: 6.0
        )
        XCTAssertFalse(deload, "Moderate fatigue off-cycle should NOT deload")
    }

    func testLearnedIncrementOverridesEquipmentDefault() {
        let ex = compoundExercise() // barbell, default 2.5
        let hist = [
            history(daysAgo: 2, weight: 100, reps: 8, avgRPE: 5, worstForm: .clean, sampleCount: 3),
            history(daysAgo: 5, weight: 100, reps: 8, avgRPE: 5, worstForm: .clean, sampleCount: 3),
        ]
        // Learned increment 4.0 → easy accel doubles to 8.0.
        let d = engine.calculateProgressiveOverload(for: ex, history: hist, learnedIncrement: 4.0)
        XCTAssertEqual(d.deltaApplied, 8.0, accuracy: 0.01, "Learned increment should drive the step, not the equipment default")
    }

    // MARK: - Determinism guard (protect the floor)

    @MainActor
    func testProgressionIsDeterministic() {
        let ex = compoundExercise()
        let hist = [
            history(daysAgo: 2, weight: 100, reps: 8, avgRPE: 5, worstForm: .clean, sampleCount: 3),
            history(daysAgo: 5, weight: 100, reps: 8, avgRPE: 5, worstForm: .clean, sampleCount: 3),
        ]
        let first = engine.calculateProgressiveOverload(for: ex, history: hist)
        let second = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(first, second, "Identical input must yield identical ProgressionDecision")
    }
}
