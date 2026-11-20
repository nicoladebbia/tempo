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
import SwiftData
import XCTest

@MainActor
final class PersonalRecordDetectionTests: XCTestCase {
    private var engine: TrainingEngine!
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        engine = TrainingEngine()
        container = try TempoModelContainer.create(inMemory: true)
        context = container.mainContext
    }

    private func bareExercise(_ equipment: Equipment = .barbell) -> Exercise {
        let exercise = Exercise(
            name: "Bench Press",
            muscleGroup: .chest,
            equipment: equipment,
            movementPattern: .horizontalPush,
            isCompound: true
        )
        context.insert(exercise)
        return exercise
    }

    /// A lift with one earlier session (60 × 5) — the first log of a lift is
    /// only a baseline, so record tests need something before them.
    private func exercise() -> Exercise {
        let exercise = bareExercise()
        addHistory(to: exercise, weight: 60, reps: 5)
        return exercise
    }

    private func addHistory(to exercise: Exercise, weight: Double, reps: Int, planID: UUID? = UUID()) {
        let row = ExerciseHistory(
            date: Date().addingTimeInterval(-7 * 86400),
            estimated1RM: weight > 0 ? StrengthStandards.epleyE1RM(weight: weight, reps: reps) : nil,
            bestSetWeight: weight,
            bestSetReps: reps,
            workoutPlanID: planID,
            exercise: exercise
        )
        context.insert(row)
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

    // MARK: - RIR-aware e1RM (matches PlannedSet.estimated1RM / history)

    func testPRValueUsesSameRIRAwareFormulaAsHistory() throws {
        let pr = try XCTUnwrap(engine.detectPersonalRecord(
            exercise: exercise(), weight: 100, reps: 5, rir: 2, workoutPlanID: nil
        ))
        XCTAssertEqual(pr.value, StrengthStandards.e1RM(weight: 100, reps: 5, rir: 2), accuracy: 0.001)
    }

    func testSamePerformanceAsLegacyPRIsNotANewPR() throws {
        let bench = bareExercise()
        // Stored before e1RM became RIR-aware: plain Epley of 100 x 5.
        let legacy = PersonalRecord(
            type: .oneRepMax, value: StrengthStandards.epleyE1RM(weight: 100, reps: 5), date: Date(),
            context: "100 x 5 reps", contextWeightKg: 100, contextReps: 5, exercise: bench
        )
        context.insert(legacy)
        try context.save()

        let same = engine.detectPersonalRecord(exercise: bench, weight: 100, reps: 5, rir: 2, workoutPlanID: nil)
        XCTAssertNotEqual(same?.type, .oneRepMax, "Same lift, only a higher RIR assumption — no e1RM PR")

        let better = engine.detectPersonalRecord(exercise: bench, weight: 102.5, reps: 5, rir: 2, workoutPlanID: nil)
        XCTAssertEqual(better?.type, .oneRepMax)
    }

    // MARK: - Round 1 PR rules

    func testFirstEverLogIsABaselineNotAPR() {
        XCTAssertNil(
            engine.detectPersonalRecord(exercise: bareExercise(), weight: 100, reps: 5, workoutPlanID: UUID()),
            "Nothing to beat yet — the first session sets the bar"
        )
    }

    func testTodaysOwnRowsDoNotRaiseTheBar() throws {
        let bench = exercise()
        let today = UUID()
        context.insert(PersonalRecord(
            type: .oneRepMax, value: 200, date: Date(), workoutPlanID: today,
            contextWeightKg: 180, contextReps: 3, exercise: bench
        ))
        // Compared with the earlier 60 × 5 session only — the VM upgrades
        // today's row in place.
        let pr = try XCTUnwrap(engine.detectPersonalRecord(exercise: bench, weight: 100, reps: 5, workoutPlanID: today))
        XCTAssertEqual(pr.type, .oneRepMax)
    }

    func testHeaviestWeightOnlyWhenNotAnE1RMRecord() throws {
        let bench = bareExercise()
        addHistory(to: bench, weight: 100, reps: 8)
        // Heavier single, but a lower e1RM than 100 × 8.
        let pr = try XCTUnwrap(engine.detectPersonalRecord(exercise: bench, weight: 105, reps: 1, rir: 0, workoutPlanID: UUID()))
        XCTAssertEqual(pr.type, .repMax)
        XCTAssertEqual(pr.value, 105)
        XCTAssertEqual(PRDisplay.subtitle(pr), "Heaviest weight · 1 rep")
        // Same weight again is nothing.
        XCTAssertNil(engine.detectPersonalRecord(exercise: bench, weight: 100, reps: 2, rir: 0, workoutPlanID: UUID()))
    }

    func testBodyweightMostReps() throws {
        let pullUp = bareExercise(.bodyweight)
        addHistory(to: pullUp, weight: 0, reps: 10)
        XCTAssertNil(engine.detectPersonalRecord(exercise: pullUp, weight: 0, reps: 10, workoutPlanID: UUID()))
        let pr = try XCTUnwrap(engine.detectPersonalRecord(exercise: pullUp, weight: 0, reps: 12, workoutPlanID: UUID()))
        XCTAssertEqual(pr.type, .mostReps)
        XCTAssertEqual(pr.value, 12)
        XCTAssertEqual(PRDisplay.valueLabel(pr, unit: .kg), "12 reps")
    }

    func testRoundingNoiseIsNotARecord() {
        let bench = bareExercise()
        addHistory(to: bench, weight: 100, reps: 5)
        XCTAssertNil(
            engine.detectPersonalRecord(exercise: bench, weight: 100.01, reps: 5, rir: 0, workoutPlanID: UUID()),
            "A kg↔lb round-trip echo of the same lift is not a PR"
        )
    }
}
