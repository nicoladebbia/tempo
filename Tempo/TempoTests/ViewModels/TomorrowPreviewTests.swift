//
// TomorrowPreviewTests.swift
// Tempo
//
// The Tomorrow card's data: rows carry sets x reps @ weight, and building the
// preview never persists a tomorrow WorkoutPlan / PlannedExercise / prediction
// (the Sunday path populates a scratch plan and must clean it up).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TomorrowPreviewTests: XCTestCase {
    private var context: ModelContext!
    private var vm: TrainingViewModel!

    override func setUpWithError() throws {
        let container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        let defs: [(String, MuscleGroup, Equipment, MovementPattern, Bool)] = [
            ("Barbell Bench Press", .chest, .barbell, .horizontalPush, true),
            ("Overhead Press", .shoulders, .barbell, .verticalPush, true),
            ("Barbell Row", .back, .barbell, .horizontalPull, true),
            ("Pull-Up", .back, .pullUpBar, .verticalPull, true),
            ("Barbell Squat", .quads, .barbell, .squat, true),
            ("Romanian Deadlift", .hamstrings, .barbell, .hinge, true),
            ("Tricep Pushdown", .triceps, .cable, .isolation, false),
            ("Barbell Curl", .biceps, .barbell, .isolation, false),
            ("Leg Extension", .quads, .machine, .isolation, false),
        ]
        for d in defs {
            context.insert(Exercise(name: d.0, muscleGroup: d.1, equipment: d.2, movementPattern: d.3, isCompound: d.4))
        }
        context.insert(UserSettings())
        try context.save()
        vm = TrainingViewModel(trainingEngine: TrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService())
    }

    private func counts() throws -> (plans: Int, slots: Int, sets: Int, predictions: Int) {
        (
            try context.fetchCount(FetchDescriptor<WorkoutPlan>()),
            try context.fetchCount(FetchDescriptor<PlannedExercise>()),
            try context.fetchCount(FetchDescriptor<PlannedSet>()),
            try context.fetchCount(FetchDescriptor<PredictionLog>())
        )
    }

    func testPreviewFromThePopulatedWeekHasRowsWithSetsRepsWeight() throws {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let plan = WorkoutPlan(date: tomorrow, type: .push)
        vm.weekPlans = [plan]
        vm.populateExercises(for: plan, modelContext: context, recordPrediction: false)

        let preview = try XCTUnwrap(vm.tomorrowPreview(modelContext: context))
        XCTAssertEqual(preview.type, .push)
        XCTAssertFalse(preview.rows.isEmpty)
        let bench = try XCTUnwrap(preview.rows.first { $0.name == "Barbell Bench Press" })
        XCTAssertGreaterThanOrEqual(bench.workingSets, 3)
        XCTAssertTrue(bench.detail(unit: .kg).contains("\(bench.workingSets)×\(bench.reps)"))
        XCTAssertTrue(bench.detail(unit: .kg).contains("kg"))
    }

    func testBodyweightLiftReadsBWNotAZeroWeight() {
        let row = TomorrowPreview.Row(id: 0, name: "Pull-Up", workingSets: 3, reps: 8,
                                      targetWeightKg: 80, addedLoadKg: nil, isBodyweight: true)
        XCTAssertEqual(row.detail(unit: .kg), "3×8 (BW)")
    }

    /// Sunday path: weekPlans holds no entry for tomorrow, so the preview is
    /// built from a fresh transient plan. Nothing may be left behind (T4).
    func testSundayStylePreviewLeavesNoRowsBehind() throws {
        vm.weekPlans = []
        let before = try counts()
        let preview = try XCTUnwrap(vm.tomorrowPreview(modelContext: context))
        try context.save()
        let after = try counts()
        XCTAssertEqual(after.plans, before.plans, "no tomorrow WorkoutPlan persisted")
        XCTAssertEqual(after.slots, before.slots)
        XCTAssertEqual(after.sets, before.sets)
        XCTAssertEqual(after.predictions, before.predictions, "no PredictionLog for tomorrow")
        if preview.isGym {
            XCTAssertFalse(preview.rows.isEmpty, "gym day shows its exercises")
        }
    }

    func testRebalanceNoteSurfaces() throws {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let plan = WorkoutPlan(date: tomorrow, type: .push)
        plan.notes = "Adjusted: yesterday's soccer + pull. Pull became push"
        vm.weekPlans = [plan]
        let preview = try XCTUnwrap(vm.tomorrowPreview(modelContext: context))
        XCTAssertEqual(preview.note, "Adjusted: yesterday's soccer + pull. Pull became push")
    }
}
