//
// PersonalRecordDetectionTests.swift
// Tempo
//
// §12 — `detectPersonalRecord` used to hand-roll a Brzycki e1RM
// (`weight*36/(37-reps)`, undefined at 37 reps and NEGATIVE above it), which
// also disagreed with the Epley formula every other e1RM in the app uses
// (PlannedSet.estimated1RM, StrengthStandards.epleyE1RM). It now shares that
// formula, a rep cap keeps a very-high-rep set from minting a nonsense e1RM
// PR, and the PR is stamped with the workoutPlanID that produced it (§13) with
// a unit-neutral context string (never bakes in "kg").
//

@testable import Tempo
import XCTest

@MainActor
final class PersonalRecordDetectionTests: XCTestCase {
    private var engine: TrainingEngine!

    override func setUp() {
        super.setUp()
        engine = TrainingEngine()
    }

    private func exercise() -> Exercise {
        Exercise(
            name: "Bench Press",
            muscleGroup: .chest,
            equipment: .barbell,
            movementPattern: .horizontalPush,
            isCompound: true
        )
    }

    func testUsesEpleyNotBrzyckiForE1RM() throws {
        // Epley: 100 * (1 + 5/30) ≈ 116.667. The old hand-rolled Brzycki gave
        // 100 * 36/(37-5) = 112.5 — a different number the rest of the app
        // (PlannedSet.estimated1RM / StrengthStandards.epleyE1RM) never used.
        let pr = try XCTUnwrap(engine.detectPersonalRecord(
            exercise: exercise(), weight: 100, reps: 5, workoutPlanID: nil
        ))
        XCTAssertEqual(pr.value, StrengthStandards.epleyE1RM(weight: 100, reps: 5), accuracy: 0.001)
        XCTAssertNotEqual(pr.value, 112.5, accuracy: 0.1, "must not be the old hand-rolled Brzycki value")
    }

    func testEpleyStaysFiniteWellPastTheOldBrzyckiSingularity() {
        // The old formula divides by (37 - reps): undefined at reps == 37,
        // negative above it. The shared Epley formula must never do that.
        let e1rm = StrengthStandards.epleyE1RM(weight: 20, reps: 40)
        XCTAssertTrue(e1rm.isFinite)
        XCTAssertGreaterThan(e1rm, 0)

        // A 40-rep set can still legitimately be a REP-MAX PR ("heaviest
        // weight moved for 3+ reps"), but it must never be recorded as a
        // ONE-REP-MAX PR — an e1RM estimate that far out is not trustworthy.
        let pr = engine.detectPersonalRecord(exercise: exercise(), weight: 20, reps: 40, workoutPlanID: nil)
        XCTAssertNotEqual(pr?.type, .oneRepMax)
    }

    func testRepsAboveTheCapDoNotCountTowardAnE1RMPR() {
        // 13 reps is one past the cap (12). Even though the raw e1RM would
        // clear any prior best (there is none — currentPR == 0), it must not
        // mint a ONE-REP-MAX PR. (It may still legitimately be a rep-max PR —
        // that path is independent of e1RM trustworthiness.)
        let pr = engine.detectPersonalRecord(exercise: exercise(), weight: 100, reps: 13, workoutPlanID: nil)
        XCTAssertNotEqual(pr?.type, .oneRepMax, "reps above the e1RM PR rep cap must not mint an e1RM PR")
    }

    func testRepsAtTheCapStillCountTowardAnE1RMPR() throws {
        let pr = try XCTUnwrap(engine.detectPersonalRecord(
            exercise: exercise(), weight: 100, reps: TrainingEngine.e1RMPersonalRecordRepCap, workoutPlanID: nil
        ))
        XCTAssertEqual(pr.type, .oneRepMax, "reps AT the cap must still count")
    }

    func testStampsTheWorkoutPlanIDThatProducedIt() throws {
        let planID = UUID()
        let pr = try XCTUnwrap(engine.detectPersonalRecord(
            exercise: exercise(), weight: 100, reps: 5, workoutPlanID: planID
        ))
        XCTAssertEqual(pr.workoutPlanID, planID, "§13 — lets WorkoutHistoryView's delete cleanup match this PR exactly")
    }

    func testContextIsUnitNeutralAndStructuredFieldsAreSet() throws {
        let pr = try XCTUnwrap(engine.detectPersonalRecord(
            exercise: exercise(), weight: 100, reps: 5, workoutPlanID: nil
        ))
        XCTAssertFalse(
            (pr.context ?? "").lowercased().contains("kg"),
            "context must never claim a unit — `value`/`contextWeightKg` are kg internally, but a display reading raw `context` could be showing a lbs user's number"
        )
        XCTAssertEqual(pr.contextWeightKg, 100)
        XCTAssertEqual(pr.contextReps, 5)
    }
}
