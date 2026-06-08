//
// ProgressiveOverloadFeedbackTests.swift
// Tempo
//
// Tier 2 — feedback-aware progressive overload. calculateProgressiveOverload is
// a pure (Exercise, [ExerciseHistory]) -> (weight, reps) function, so these run
// with no device. Rules under test:
//   - No feedback (nil aggregates / legacy rows) → behaves as rep-count only.
//   - Last session avgRPE >= 9 → HOLD (do not progress) even if reps were hit.
//   - Last session worst form sloppy/failed → HOLD.
//   - avgRPE <= 6 + hit reps → progress at the normal increment (no double jump).
//

@testable import Tempo
import XCTest

final class ProgressiveOverloadFeedbackTests: XCTestCase {
    private var engine: TrainingEngine!

    override func setUp() {
        super.setUp()
        engine = TrainingEngine()
    }

    // MARK: - Helpers

    private func compoundExercise() -> Exercise {
        Exercise(
            name: "Barbell Row",
            muscleGroup: .back,
            equipment: .barbell,
            movementPattern: .horizontalPull,
            isCompound: true
        )
    }

    /// Build a history row. `date` ordering matters (engine sorts desc).
    private func history(
        daysAgo: Int,
        weight: Double,
        reps: Int,
        avgRPE: Double? = nil,
        worstForm: FormQuality? = nil,
        sampleCount: Int = 0
    ) -> ExerciseHistory {
        ExerciseHistory(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            bestSetWeight: weight,
            bestSetReps: reps,
            avgRPE: avgRPE,
            worstFormRaw: worstForm?.rawValue,
            feedbackSampleCount: sampleCount
        )
    }

    // MARK: - Regression: no feedback behaves as before

    @MainActor
    func testNoFeedbackProgressesOnRepsAsBefore() {
        let ex = compoundExercise()
        // Two successful sessions (hit 8 reps), no feedback → should increase.
        let hist = [
            history(daysAgo: 2, weight: 60, reps: 8),
            history(daysAgo: 5, weight: 60, reps: 8),
        ]
        let result = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertGreaterThan(result.weight, 60, "No feedback + reps hit should still progress")
    }

    // MARK: - High RPE holds

    @MainActor
    func testHighRPEHoldsEvenWhenRepsHit() {
        let ex = compoundExercise()
        // Reps hit (would normally progress) but last session felt maximal.
        let hist = [
            history(daysAgo: 2, weight: 60, reps: 8, avgRPE: 9.5, worstForm: .clean, sampleCount: 3),
            history(daysAgo: 5, weight: 60, reps: 8, avgRPE: 8, worstForm: .clean, sampleCount: 3),
        ]
        let result = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(result.weight, 60, "avgRPE >= 9 last session should HOLD, not progress")
    }

    // MARK: - Bad form holds

    @MainActor
    func testSloppyFormHolds() {
        let ex = compoundExercise()
        let hist = [
            history(daysAgo: 2, weight: 60, reps: 8, avgRPE: 7, worstForm: .sloppy, sampleCount: 3),
            history(daysAgo: 5, weight: 60, reps: 8, avgRPE: 7, worstForm: .clean, sampleCount: 3),
        ]
        let result = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(result.weight, 60, "Sloppy form last session should HOLD")
    }

    @MainActor
    func testFailedFormHolds() {
        let ex = compoundExercise()
        let hist = [
            history(daysAgo: 2, weight: 60, reps: 8, avgRPE: 7, worstForm: .failed, sampleCount: 2),
            history(daysAgo: 5, weight: 60, reps: 8, avgRPE: 7, worstForm: .clean, sampleCount: 2),
        ]
        let result = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(result.weight, 60, "Failed form last session should HOLD")
    }

    // MARK: - Easy + reps hit → ACCELERATED (Phase 1 sizing, contract change)

    // NOTE: this is a deliberate contract change from the original Tier-2 design.
    // Previously avgRPE <= 6 progressed at a single increment ("no double jump").
    // Phase 1 (TRAINING_INTELLIGENCE_TO_10.md Fix 1.1) SIZES the jump: a clearly
    // easy session (avgRPE <= 6.5) earns a double increment, clamped to exactly
    // one extra step, so an under-loaded lifter catches up. The veto rules
    // (high RPE / broken form hold) are unchanged.
    @MainActor
    func testEasyAndRepsHitAccelerates() {
        let ex = compoundExercise()
        let hist = [
            history(daysAgo: 2, weight: 60, reps: 8, avgRPE: 6, worstForm: .clean, sampleCount: 3),
            history(daysAgo: 5, weight: 60, reps: 8, avgRPE: 6, worstForm: .clean, sampleCount: 3),
        ]
        let result = engine.calculateProgressiveOverload(for: ex, history: hist)
        // Barbell increment 2.5kg, doubled to 5.0 for an easy clean session.
        XCTAssertEqual(result.weight, 65.0, accuracy: 0.01, "Easy + reps hit → double increment (accelerated)")
        XCTAssertEqual(result.deltaApplied, 5.0, accuracy: 0.01)
        XCTAssertEqual(result.rationale, .acceleratedEasyLoad)
    }

    // A merely-normal session (RPE just above the easy threshold) progresses at
    // the standard single increment — the acceleration is gated, not automatic.
    @MainActor
    func testNormalRPEProgressesStandardIncrement() {
        let ex = compoundExercise()
        let hist = [
            history(daysAgo: 2, weight: 60, reps: 8, avgRPE: 7.5, worstForm: .clean, sampleCount: 3),
            history(daysAgo: 5, weight: 60, reps: 8, avgRPE: 7.5, worstForm: .clean, sampleCount: 3),
        ]
        let result = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertEqual(result.weight, 62.5, accuracy: 0.01, "Normal RPE → single increment")
        XCTAssertEqual(result.rationale, .standardProgression)
    }

    // MARK: - Legacy rows (no feedback fields) treated as no-signal

    @MainActor
    func testLegacyRowsTreatedAsNoSignal() {
        let ex = compoundExercise()
        // sampleCount 0 + nil aggregates = legacy / no real feedback.
        let hist = [
            history(daysAgo: 2, weight: 60, reps: 8, avgRPE: nil, worstForm: nil, sampleCount: 0),
            history(daysAgo: 5, weight: 60, reps: 8, avgRPE: nil, worstForm: nil, sampleCount: 0),
        ]
        let result = engine.calculateProgressiveOverload(for: ex, history: hist)
        XCTAssertGreaterThan(result.weight, 60, "Legacy/no-signal rows must progress on reps, never treat nil as RPE 0")
    }
}
