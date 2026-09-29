//
// PersistCompletionHistoryTests.swift
// Tempo
//
// persistCompletion must leave exactly one ExerciseHistory row per logged
// exercise. It used to build extra throwaway rows (bound to the live Exercise)
// just to feed the adaptive-profile updater; SwiftData can auto-insert those.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PersistCompletionHistoryTests: XCTestCase {
    func testPersistCompletionWritesExactlyOneHistoryRowPerExercise() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        let context = ModelContext(container)
        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )

        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.status = .inProgress
        context.insert(plan)
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
                             movementPattern: .horizontalPush, isCompound: true)
        context.insert(bench)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        slot.sets = (1 ... 2).map { PlannedSet(setNumber: $0, targetReps: 8, targetWeight: 80, plannedExercise: slot) }
        try context.save()
        vm.todayPlan = plan
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        vm.skipRest()
        vm.updateFeedback(rpe: 8, modelContext: context)
        vm.logSet(weight: 80, reps: 8, modelContext: context)
        vm.updateFeedback(rpe: 9, modelContext: context)

        XCTAssertTrue(vm.persistCompletion(modelContext: context))

        let rows = try context.fetch(FetchDescriptor<ExerciseHistory>())
        XCTAssertEqual(rows.count, 1, "No phantom history rows from the adaptive-profile feed")
        XCTAssertEqual(rows.first?.setsPerformed, 2)
        vm.resetState()
    }
}
