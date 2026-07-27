//
// SwapAddExerciseTests.swift
// Tempo
//
// §2.13 / §2.14 — swap-exercise and add-exercise flows. Pins the invariants:
// a swap keeps the slot but rebuilds the prescription for the new movement,
// refuses once any set is logged (completed work is never re-attributed),
// and cleans up the old movement's unresolved prediction; add appends a fully
// prescribed slot and refuses duplicates. Alternatives are same-muscle-group
// only and exclude movements already in the plan.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class SwapAddExerciseTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutPlan.self,
            Exercise.self,
            PlannedExercise.self,
            PlannedSet.self,
            PredictionLog.self,
            AdaptiveProfile.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    private func bench() -> Exercise {
        Exercise(name: "Barbell Bench Press", muscleGroup: .chest,
                 equipment: .barbell, movementPattern: .horizontalPush, isCompound: true)
    }

    private func cableFly() -> Exercise {
        Exercise(name: "Cable Fly", muscleGroup: .chest,
                 equipment: .cable, movementPattern: .isolation, isCompound: false)
    }

    /// A .planned plan holding one compound slot: 2 warmups + 3 working sets.
    private func seedPlan(
        with exercise: Exercise, context: ModelContext
    ) -> (plan: WorkoutPlan, slot: PlannedExercise) {
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        context.insert(exercise)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: exercise)
        var sets: [PlannedSet] = []
        for (i, warm) in [true, true, false, false, false].enumerated() {
            sets.append(PlannedSet(
                setNumber: i + 1, targetReps: 8, targetWeight: warm ? 40 : 80,
                isWarmup: warm, plannedExercise: slot
            ))
        }
        slot.sets = sets
        try? context.save()
        return (plan, slot)
    }

    // MARK: - Swap

    func testSwapReplacesMovementAndRebuildsPrescription() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (_, slot) = seedPlan(with: bench(), context: context)
        let fly = cableFly()
        context.insert(fly)

        vm.swapExercise(slot, with: fly, modelContext: context)

        XCTAssertEqual(slot.exercise?.name, "Cable Fly", "The movement swaps in place")
        let sets = slot.orderedSets
        XCTAssertTrue(sets.allSatisfy { !$0.isWarmup },
                      "An isolation gets no warmup ramp")
        XCTAssertEqual(sets.count, 3, "The slot's working-set count is preserved")
        XCTAssertEqual(sets.first?.targetReps, 12, "Reps re-prescribe for the new movement")
        XCTAssertEqual(sets.first?.targetWeight, 80, "Weight comes from the engine's prescription")
    }

    func testSwapRefusedOnceASetIsCompleted() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (_, slot) = seedPlan(with: bench(), context: context)
        slot.orderedSets.last?.completed = true
        let fly = cableFly()
        context.insert(fly)

        vm.swapExercise(slot, with: fly, modelContext: context)

        XCTAssertEqual(slot.exercise?.name, "Barbell Bench Press",
                       "Logged work pins the movement — no swap after a completed set")
        XCTAssertEqual(slot.orderedSets.count, 5, "Sets untouched")
    }

    func testSwapReplacesUnresolvedPrediction() throws {
        let context = try makeContext()
        let vm = makeVM()
        let old = bench()
        let (plan, slot) = seedPlan(with: old, context: context)
        let stale = PredictionLog(
            exercise: old, exerciseID: old.id, workoutPlanID: plan.id,
            predictedWeight: 80, predictedReps: 8,
            signalUsedRaw: ProgressionReason.standardProgression.rawValue,
            learnedIncrementUsed: nil, baselineWeight: nil
        )
        context.insert(stale)
        try context.save()
        let fly = cableFly()
        context.insert(fly)

        vm.swapExercise(slot, with: fly, modelContext: context)

        let rows = try context.fetch(FetchDescriptor<PredictionLog>())
        XCTAssertFalse(rows.contains { $0.exerciseID == old.id },
                       "The swapped-out movement's unresolved prediction is dropped")
        XCTAssertTrue(rows.contains { $0.exerciseID == fly.id },
                      "The new movement's prescription is logged in its place")
    }

    // MARK: - Add

    func testAddExerciseAppendsWithPrescription() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (plan, _) = seedPlan(with: bench(), context: context)
        vm.todayPlan = plan
        let fly = cableFly()
        context.insert(fly)

        vm.addExercise(fly, modelContext: context)

        let slots = plan.orderedExercises
        XCTAssertEqual(slots.count, 2, "The new movement appends to the plan")
        let added = slots.last
        XCTAssertEqual(added?.exercise?.name, "Cable Fly")
        XCTAssertEqual(added?.order, 1, "Appends after the existing slots")
        XCTAssertEqual(added?.orderedSets.count, 3, "Three working sets by default")
        XCTAssertEqual(added?.orderedSets.first?.targetReps, 12)
    }

    func testAddExerciseRefusesDuplicates() throws {
        let context = try makeContext()
        let vm = makeVM()
        let ex = bench()
        let (plan, _) = seedPlan(with: ex, context: context)
        vm.todayPlan = plan

        vm.addExercise(ex, modelContext: context)

        XCTAssertEqual(plan.orderedExercises.count, 1,
                       "A movement already in the plan is never added twice")
    }

    // MARK: - Alternatives

    func testSwapAlternativesSameMuscleGroupExcludingPlan() throws {
        let context = try makeContext()
        let vm = makeVM()
        let (_, slot) = seedPlan(with: bench(), context: context)
        let incline = Exercise(name: "Incline Dumbbell Press", muscleGroup: .chest,
                               equipment: .dumbbell, movementPattern: .horizontalPush,
                               isCompound: true)
        let fly = cableFly()
        let row = Exercise(name: "Barbell Row", muscleGroup: .back,
                           equipment: .barbell, movementPattern: .horizontalPull,
                           isCompound: true)
        [incline, fly, row].forEach { context.insert($0) }
        try context.save()

        let names = vm.swapAlternatives(for: slot, modelContext: context).map(\.name)

        XCTAssertEqual(names.first, "Incline Dumbbell Press",
                       "Same movement pattern ranks first — the closest substitute")
        XCTAssertTrue(names.contains("Cable Fly"), "Same muscle group qualifies")
        XCTAssertFalse(names.contains("Barbell Row"), "Other muscle groups excluded")
        XCTAssertFalse(names.contains("Barbell Bench Press"),
                       "The movement being swapped is not its own alternative")
    }
}
