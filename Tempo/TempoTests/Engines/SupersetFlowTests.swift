//
// SupersetFlowTests.swift
// Tempo
//
// §6 / §2.8 — the active-workout superset flow. Pins the alternation
// invariants: A1 → B1 with NO rest, ONE shared rest after the second lift
// leading back to the first, warmup ramps excluded from alternation, and a
// finished pair advancing PAST the partner (never landing on an
// already-logged exercise). autoStartRest is off in these tests so the jump
// happens synchronously through the same advanceAfterRest path the timer uses.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class SupersetFlowTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutPlan.self,
            Exercise.self,
            PlannedExercise.self,
            PlannedSet.self,
            SetFeedback.self,
            PersonalRecord.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
        vm.autoStartRest = false
        return vm
    }

    /// Plan: superset pair A (workingA sets) + B (workingB sets), then an
    /// optional trailing standalone exercise. Warmups prepend to A on request.
    private func seedSupersetPlan(
        workingA: Int,
        workingB: Int,
        warmupsOnA: Int = 0,
        trailingExercise: Bool = false,
        context: ModelContext
    ) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)

        let a = Exercise(name: "Bench Press", muscleGroup: .chest,
                         equipment: .barbell, movementPattern: .horizontalPush, isCompound: true)
        let b = Exercise(name: "Lateral Raise", muscleGroup: .shoulders,
                         equipment: .dumbbell, movementPattern: .isolation, isCompound: false)
        context.insert(a)
        context.insert(b)

        let slotA = PlannedExercise(order: 0, supersetGroup: 1, workoutPlan: plan, exercise: a)
        var setsA: [PlannedSet] = []
        var num = 1
        for _ in 0 ..< warmupsOnA {
            setsA.append(PlannedSet(setNumber: num, targetReps: 8, targetWeight: 40,
                                    isWarmup: true, plannedExercise: slotA))
            num += 1
        }
        for _ in 0 ..< workingA {
            setsA.append(PlannedSet(setNumber: num, targetReps: 8, targetWeight: 80,
                                    plannedExercise: slotA))
            num += 1
        }
        slotA.sets = setsA

        let slotB = PlannedExercise(order: 1, supersetGroup: 1, workoutPlan: plan, exercise: b)
        slotB.sets = (1 ... workingB).map {
            PlannedSet(setNumber: $0, targetReps: 12, targetWeight: 10, plannedExercise: slotB)
        }

        if trailingExercise {
            let c = Exercise(name: "Tricep Pushdown", muscleGroup: .triceps,
                             equipment: .cable, movementPattern: .isolation, isCompound: false)
            context.insert(c)
            let slotC = PlannedExercise(order: 2, workoutPlan: plan, exercise: c)
            slotC.sets = [PlannedSet(setNumber: 1, targetReps: 12, targetWeight: 25,
                                     plannedExercise: slotC)]
        }
        try? context.save()
        return plan
    }

    private func position(_ vm: TrainingViewModel) -> (ex: Int, set: Int) {
        (vm.currentExerciseIndex, vm.currentSetIndex)
    }

    // MARK: - Alternation

    func testFirstLiftJumpsToPartnerWithNoRest() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedSupersetPlan(workingA: 3, workingB: 3, context: context)
        vm.autoStartRest = true // even with auto-rest ON, A → B takes none

        vm.logSet(weight: 80, reps: 8, modelContext: context)

        XCTAssertEqual(position(vm).ex, 1, "A1 flows straight into B")
        XCTAssertEqual(position(vm).set, 0)
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 1, setIndex: 0)),
                       "No resting state between the pair's lifts")
    }

    func testSecondLiftRestsThenReturnsToFirst() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedSupersetPlan(workingA: 3, workingB: 3, context: context)

        vm.logSet(weight: 80, reps: 8, modelContext: context) // A1 → B
        vm.logSet(weight: 10, reps: 12, modelContext: context) // B1 → back to A

        XCTAssertEqual(position(vm).ex, 0, "The pair's rest leads back to the first lift")
        XCTAssertEqual(position(vm).set, 1, "A's next uncompleted set")
    }

    func testFullAlternationEndsInSummary() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedSupersetPlan(workingA: 2, workingB: 2, context: context)

        vm.logSet(weight: 80, reps: 8, modelContext: context) // A1 → B1
        vm.logSet(weight: 10, reps: 12, modelContext: context) // B1 → A2
        vm.logSet(weight: 80, reps: 8, modelContext: context) // A2 → B2
        vm.logSet(weight: 10, reps: 12, modelContext: context) // B2 → done

        XCTAssertEqual(vm.sessionState, .summary, "Both lifts fully logged → summary")
    }

    func testUnevenPairFinishesLongerLiftSequentially() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedSupersetPlan(workingA: 3, workingB: 1, context: context)

        vm.logSet(weight: 80, reps: 8, modelContext: context) // A1 → B1
        vm.logSet(weight: 10, reps: 12, modelContext: context) // B1 (B done) → A2
        vm.logSet(weight: 80, reps: 8, modelContext: context) // A2, partner done → A3

        XCTAssertEqual(position(vm).ex, 0, "With B finished, A continues in the normal flow")
        XCTAssertEqual(position(vm).set, 2)

        vm.logSet(weight: 80, reps: 8, modelContext: context) // A3 — pair complete
        XCTAssertEqual(vm.sessionState, .summary)
    }

    func testWarmupSetsStayInNormalFlow() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedSupersetPlan(workingA: 2, workingB: 2, warmupsOnA: 1, context: context)

        vm.logSet(weight: 40, reps: 8, modelContext: context) // A warmup — no jump

        XCTAssertEqual(position(vm).ex, 0, "A warmup ramp never triggers the alternation")
        XCTAssertEqual(position(vm).set, 1)
    }

    // MARK: - Pair completion never lands on the finished partner

    func testFinishedPairAdvancesPastPartner() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedSupersetPlan(
            workingA: 1, workingB: 1, trailingExercise: true, context: context
        )

        vm.logSet(weight: 80, reps: 8, modelContext: context) // A1 → B1
        vm.logSet(weight: 10, reps: 12, modelContext: context) // B1 — pair complete

        XCTAssertEqual(position(vm).ex, 2,
                       "A finished pair advances to the exercise AFTER it, not back onto the partner")
        XCTAssertEqual(position(vm).set, 0)
    }

    // MARK: - Non-superset flow untouched

    func testStandaloneExerciseKeepsSequentialFlow() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        let ex = Exercise(name: "Overhead Press", muscleGroup: .shoulders,
                          equipment: .barbell, movementPattern: .verticalPush, isCompound: true)
        context.insert(ex)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: ex)
        slot.sets = (1 ... 2).map {
            PlannedSet(setNumber: $0, targetReps: 8, targetWeight: 60, plannedExercise: slot)
        }
        try context.save()
        vm.todayPlan = plan

        vm.logSet(weight: 60, reps: 8, modelContext: context)

        XCTAssertEqual(position(vm).ex, 0, "No superset group → the standard next-set flow")
        XCTAssertEqual(position(vm).set, 1)
    }
}
