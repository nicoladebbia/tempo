//
// CustomExerciseTests.swift
// Tempo
//
// §10.6 — a created custom exercise must be a first-class library citizen:
// the engine's group-based selection programmes it into matching workout
// days, and the swap sheet offers it as an alternative. (The creation form
// itself is UI; these pin the paths that make the created row USEFUL.)
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CustomExerciseTests: XCTestCase {
    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    func testCustomExerciseIsSelectedForMatchingWorkoutType() {
        let vm = makeVM()
        let custom = Exercise(name: "Landmine Press", muscleGroup: .chest,
                              equipment: .barbell, movementPattern: .horizontalPush,
                              isCompound: true, isCustom: true)

        let selected = vm.selectExercises(
            from: [custom], targetGroups: [.chest, .shoulders, .triceps], workoutType: .push
        )

        XCTAssertTrue(selected.contains { $0.id == custom.id },
                      "Group-based selection must programme custom exercises")
    }

    func testCustomExerciseAppearsAsSwapAlternative() throws {
        let schema = Schema([WorkoutPlan.self, Exercise.self, PlannedExercise.self, PlannedSet.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let vm = makeVM()

        let bench = Exercise(name: "Barbell Bench Press", muscleGroup: .chest,
                             equipment: .barbell, movementPattern: .horizontalPush, isCompound: true)
        let custom = Exercise(name: "Landmine Press", muscleGroup: .chest,
                              equipment: .barbell, movementPattern: .horizontalPush,
                              isCompound: true, isCustom: true)
        context.insert(bench)
        context.insert(custom)
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        slot.sets = [PlannedSet(setNumber: 1, targetReps: 8, targetWeight: 80, plannedExercise: slot)]
        try context.save()

        let names = vm.swapAlternatives(for: slot, modelContext: context).map(\.name)
        XCTAssertTrue(names.contains("Landmine Press"),
                      "Custom exercises are offered as swap alternatives")
    }
}
