//
// PredictionLogSpineTests.swift
// Tempo
//
// Step 1 (measurement spine) — proves the thermometer works: a prediction
// written at prescribe time, paired to the right outcome at save time, yields
// a correct prediction↔reality record (and a correct RPE error). This is the
// foundation Step 2's "is it getting more accurate?" metric stands on.
//

@testable import Tempo
import SwiftData
import XCTest

@MainActor
final class PredictionLogSpineTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            PredictionLog.self,
            Exercise.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    private func prediction(
        planID: UUID,
        exerciseID: UUID,
        weight: Double = 100,
        reps: Int = 8,
        predictedRPE: Double = 8.0,
        rationale: ProgressionReason = .standardProgression
    ) -> PredictionLog {
        PredictionLog(
            exerciseID: exerciseID,
            workoutPlanID: planID,
            predictedWeight: weight,
            predictedReps: reps,
            predictedRPE: predictedRPE,
            signalUsedRaw: rationale.rawValue
        )
    }

    // MARK: - RPE error math (the core Step-2 signal)

    func testRPEErrorNilUntilResolved() {
        let p = prediction(planID: UUID(), exerciseID: UUID())
        XCTAssertNil(p.rpeError, "Unresolved prediction has no error yet")
    }

    func testRPEErrorPositiveWhenHarderThanPredicted() {
        let p = prediction(planID: UUID(), exerciseID: UUID(), predictedRPE: 8.0)
        p.actualRPE = 9.5
        p.outcomeResolved = true
        XCTAssertEqual(p.rpeError!, 1.5, accuracy: 0.001, "Harder than intended → positive error (over-prescribed)")
    }

    func testRPEErrorNegativeWhenEasierThanPredicted() {
        let p = prediction(planID: UUID(), exerciseID: UUID(), predictedRPE: 8.0)
        p.actualRPE = 6.0
        p.outcomeResolved = true
        XCTAssertEqual(p.rpeError!, -2.0, accuracy: 0.001, "Easier than intended → negative error (under-prescribed)")
    }

    func testRPEErrorNilWhenResolvedButNoEnteredRPE() {
        let p = prediction(planID: UUID(), exerciseID: UUID())
        p.outcomeResolved = true
        p.actualRPE = nil // session logged, no feedback entered
        XCTAssertNil(p.rpeError, "Resolved-but-no-RPE must not fabricate an error")
    }

    // MARK: - Backfill pairing

    func testBackfillMatchesByExerciseAndPlan() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = makeVM()
        let planID = UUID()
        let exA = UUID(), exB = UUID()

        context.insert(prediction(planID: planID, exerciseID: exA, predictedRPE: 8))
        context.insert(prediction(planID: planID, exerciseID: exB, predictedRPE: 8))
        try context.save()

        vm.backfillPredictionOutcomes(
            planID: planID,
            outcomes: [
                .init(exerciseID: exA, bestSetReps: 8, avgRPE: 9.0, worstFormRaw: "clean", bestSetWeight: 100),
                .init(exerciseID: exB, bestSetReps: 12, avgRPE: 6.0, worstFormRaw: "clean", bestSetWeight: 40),
            ],
            modelContext: context
        )

        let rows = try context.fetch(FetchDescriptor<PredictionLog>())
        let a = rows.first { $0.exerciseID == exA }!
        let b = rows.first { $0.exerciseID == exB }!
        XCTAssertTrue(a.outcomeResolved)
        XCTAssertEqual(a.rpeError!, 1.0, accuracy: 0.001, "exA: 9.0 actual − 8.0 predicted")
        XCTAssertEqual(b.rpeError!, -2.0, accuracy: 0.001, "exB: 6.0 actual − 8.0 predicted")
    }

    func testBackfillSkipsUnmatchedOutcome() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = makeVM()
        let planID = UUID()
        let exA = UUID()
        context.insert(prediction(planID: planID, exerciseID: exA))
        try context.save()

        // An outcome for an exercise with no prediction (added mid-session).
        vm.backfillPredictionOutcomes(
            planID: planID,
            outcomes: [.init(exerciseID: UUID(), bestSetReps: 8, avgRPE: 8, worstFormRaw: "clean", bestSetWeight: 50)],
            modelContext: context
        )
        let rows = try context.fetch(FetchDescriptor<PredictionLog>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].outcomeResolved, "Unmatched outcome must not resolve the unrelated prediction")
    }

    func testBackfillIgnoresOtherPlans() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let vm = makeVM()
        let planID = UUID(), otherPlanID = UUID()
        let exA = UUID()
        context.insert(prediction(planID: planID, exerciseID: exA))
        context.insert(prediction(planID: otherPlanID, exerciseID: exA))
        try context.save()

        vm.backfillPredictionOutcomes(
            planID: planID,
            outcomes: [.init(exerciseID: exA, bestSetReps: 8, avgRPE: 9, worstFormRaw: "clean", bestSetWeight: 100)],
            modelContext: context
        )
        let rows = try context.fetch(FetchDescriptor<PredictionLog>())
        let thisPlan = rows.first { $0.workoutPlanID == planID }!
        let otherPlan = rows.first { $0.workoutPlanID == otherPlanID }!
        XCTAssertTrue(thisPlan.outcomeResolved, "Same-exercise row on THIS plan resolves")
        XCTAssertFalse(otherPlan.outcomeResolved, "Same-exercise row on ANOTHER plan is untouched")
    }
}
