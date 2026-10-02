//
// BodyweightRecordRulesTests.swift
// Tempo
//
// Records on bodyweight-loaded lifts (bodyweight / pull-up bar) key on the
// ADDED load with only "Heaviest added load" and "Most reps" — no e1RM — while
// every other lift (including custom `.none` ones with real weights) keys on
// the weight actually lifted. Live logging and the CSV replay share these rules.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class BodyweightRecordRulesTests: XCTestCase {
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: TrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
    }

    private func lift(_ equipment: Equipment, name: String) -> Exercise {
        let exercise = Exercise(
            name: name, muscleGroup: .back, equipment: equipment,
            movementPattern: .verticalPull, isCompound: true
        )
        context.insert(exercise)
        return exercise
    }

    private func addHistory(_ exercise: Exercise, weight: Double?, added: Double? = nil, reps: Int, e1RM: Double? = nil) {
        context.insert(ExerciseHistory(
            date: Date().addingTimeInterval(-7 * 86400), estimated1RM: e1RM,
            bestSetWeight: weight, bestSetReps: reps, bestSetAddedLoadKg: added,
            workoutPlanID: UUID(), exercise: exercise
        ))
    }

    private func plan(for exercise: Exercise) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: .pull)
        plan.status = .inProgress
        plan.startedAt = Date().addingTimeInterval(-600)
        context.insert(plan)
        _ = PlannedExercise(order: 0, workoutPlan: plan, exercise: exercise)
        try? context.save()
        return plan
    }

    // MARK: Equipment.none is a loaded lift

    func testCustomLiftWithRealWeightsGetsWeightRecordsLive() throws {
        let vm = makeVM()
        let custom = lift(.none, name: "Zercher Thing")
        addHistory(custom, weight: 50, reps: 5, e1RM: 58)
        let outcome = vm.recordPersonalRecordIfAny(
            exercise: custom, weight: 70, reps: 5, rir: 0, addedLoadKg: nil, plan: plan(for: custom), modelContext: context
        )
        XCTAssertEqual(outcome, .new)
        XCTAssertNotEqual(vm.detectedPRs.first?.type, .mostReps)
        XCTAssertEqual(vm.detectedPRs.first?.contextWeightKg, 70)
    }

    func testLighterSetOnCustomLiftIsNotABogusMostReps() {
        let vm = makeVM()
        let custom = lift(.none, name: "Zercher Thing")
        addHistory(custom, weight: 50, reps: 5, e1RM: 58)
        let outcome = vm.recordPersonalRecordIfAny(
            exercise: custom, weight: 40, reps: 5, rir: 2, addedLoadKg: nil, plan: plan(for: custom), modelContext: context
        )
        XCTAssertEqual(outcome, .none)
    }

    func testCustomLiftAtZeroKgMayStillSetMostReps() {
        let engine = TrainingEngine()
        let custom = lift(.none, name: "Wall Sit Thing")
        addHistory(custom, weight: 0, reps: 10)
        XCTAssertEqual(engine.detectPersonalRecord(exercise: custom, weight: 0, reps: 12, workoutPlanID: UUID())?.type, .mostReps)
    }

    // MARK: Bodyweight-loaded: heaviest added load and most reps only

    func testWeightedPullUpNeverGetsAnE1RMRecord() throws {
        let engine = TrainingEngine()
        let pullUp = lift(.pullUpBar, name: "Pull-Up")
        addHistory(pullUp, weight: 90, added: 10, reps: 5, e1RM: 105)
        // Same added load, more reps: a better e1RM, but not a record here.
        XCTAssertNil(engine.detectPersonalRecord(exercise: pullUp, weight: 10, reps: 8, rir: 0, workoutPlanID: UUID()))
        // Heavier added load: "Heaviest added load".
        let heavier = try XCTUnwrap(engine.detectPersonalRecord(exercise: pullUp, weight: 12.5, reps: 5, rir: 0, workoutPlanID: UUID()))
        XCTAssertEqual(heavier.type, .repMax)
        XCTAssertEqual(heavier.value, 12.5)
    }

    func testOldEffectiveLoadRecordsDoNotRaiseTheAddedLoadBar() throws {
        let engine = TrainingEngine()
        let dip = lift(.bodyweight, name: "Dip")
        addHistory(dip, weight: 90, added: 10, reps: 5)
        // A legacy e1RM record whose context weight is the effective load.
        context.insert(PersonalRecord(
            type: .oneRepMax, value: 120, date: Date().addingTimeInterval(-86400), workoutPlanID: UUID(),
            context: "90 x 5 reps", contextWeightKg: 90, contextReps: 5, exercise: dip
        ))
        let pr = try XCTUnwrap(engine.detectPersonalRecord(exercise: dip, weight: 15, reps: 5, workoutPlanID: UUID()))
        XCTAssertEqual(pr.type, .repMax)
    }

    func testKeyingHelperOnlyCoversBodyweightLoadedEquipment() {
        XCTAssertTrue(TrainingEngine.usesBodyweightPRRule(.pullUpBar))
        XCTAssertTrue(TrainingEngine.usesBodyweightPRRule(.bodyweight))
        XCTAssertFalse(TrainingEngine.usesBodyweightPRRule(.none))
        XCTAssertFalse(TrainingEngine.usesBodyweightPRRule(.barbell))
    }
}
