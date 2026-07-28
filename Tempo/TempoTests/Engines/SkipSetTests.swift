//
// SkipSetTests.swift
// Tempo
//
// §2.16 — skip set / skip warmup ramp. Pins the invariants: a skipped set
// is DELETED (never left uncompleted for the superset flow to loop back
// to), no rest starts, and the advance lands on the next real work —
// same exercise, superset partner, next exercise, or summary.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class SkipSetTests: XCTestCase {
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

    /// Plan with one exercise: `warmups` ramp sets then `working` sets.
    /// Optionally a trailing second exercise with one working set.
    private func seed(
        warmups: Int,
        working: Int,
        trailing: Bool = false,
        superset: Bool = false,
        context: ModelContext
    ) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest,
                             equipment: .barbell, movementPattern: .horizontalPush, isCompound: true)
        context.insert(bench)
        let slot = PlannedExercise(order: 0, supersetGroup: superset ? 1 : nil,
                                   workoutPlan: plan, exercise: bench)
        var sets: [PlannedSet] = []
        var num = 1
        for _ in 0 ..< warmups {
            sets.append(PlannedSet(setNumber: num, targetReps: 8, targetWeight: 40,
                                   isWarmup: true, plannedExercise: slot))
            num += 1
        }
        for _ in 0 ..< working {
            sets.append(PlannedSet(setNumber: num, targetReps: 8, targetWeight: 80,
                                   plannedExercise: slot))
            num += 1
        }
        slot.sets = sets

        if trailing || superset {
            let raise = Exercise(name: "Lateral Raise", muscleGroup: .shoulders,
                                 equipment: .dumbbell, movementPattern: .isolation, isCompound: false)
            context.insert(raise)
            let second = PlannedExercise(order: 1, supersetGroup: superset ? 1 : nil,
                                         workoutPlan: plan, exercise: raise)
            second.sets = [PlannedSet(setNumber: 1, targetReps: 12, targetWeight: 10,
                                      plannedExercise: second)]
        }
        try? context.save()
        return plan
    }

    private func enterSetActive(_ vm: TrainingViewModel, exercise: Int = 0, set: Int = 0) {
        vm.currentExerciseIndex = exercise
        vm.currentSetIndex = set
        vm.sessionState = .exercise(.setActive(exerciseIndex: exercise, setIndex: set))
    }

    func testSkipDeletesSetAndStaysOnExercise() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(warmups: 0, working: 3, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        vm.skipCurrentSet(modelContext: context)

        let sets = plan.orderedExercises[0].orderedSets
        XCTAssertEqual(sets.count, 2, "The skipped set is removed, not left dangling")
        XCTAssertEqual(vm.sessionState,
                       .exercise(.setActive(exerciseIndex: 0, setIndex: 0)),
                       "Straight to the next set — no rest for work not done")
    }

    func testSkipLastSetOfLastExerciseEndsInSummary() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(warmups: 0, working: 1, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        vm.skipCurrentSet(modelContext: context)

        XCTAssertEqual(vm.sessionState, .summary)
        XCTAssertTrue(plan.orderedExercises[0].orderedSets.isEmpty)
    }

    func testSkipAdvancesToNextExerciseWhenCurrentEmpties() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(warmups: 0, working: 1, trailing: true, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        vm.skipCurrentSet(modelContext: context)

        XCTAssertEqual(vm.sessionState,
                       .exercise(.setActive(exerciseIndex: 1, setIndex: 0)))
    }

    func testSkipJumpsToSupersetPartnerFirst() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(warmups: 0, working: 1, superset: true, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        vm.skipCurrentSet(modelContext: context)

        XCTAssertEqual(vm.sessionState,
                       .exercise(.setActive(exerciseIndex: 1, setIndex: 0)),
                       "The pair's partner still has work — land there")
    }

    func testSkipRefusesCompletedSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(warmups: 0, working: 2, context: context)
        plan.orderedExercises[0].orderedSets[0].completed = true
        vm.todayPlan = plan
        enterSetActive(vm)

        vm.skipCurrentSet(modelContext: context)

        XCTAssertEqual(plan.orderedExercises[0].orderedSets.count, 2,
                       "Logged work is history — skip never deletes it")
    }

    func testSkipWarmupsDropsWholeRampAndLandsOnWorkingSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(warmups: 2, working: 3, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        vm.skipRemainingWarmups(modelContext: context)

        let sets = plan.orderedExercises[0].orderedSets
        XCTAssertEqual(sets.count, 3)
        XCTAssertTrue(sets.allSatisfy { !$0.isWarmup }, "The whole ramp is gone in one tap")
        XCTAssertEqual(vm.sessionState,
                       .exercise(.setActive(exerciseIndex: 0, setIndex: 0)),
                       "Lands on the first working set")
    }

    func testSkipWarmupsNoOpsWhenNoneRemain() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seed(warmups: 0, working: 2, context: context)
        vm.todayPlan = plan
        enterSetActive(vm)

        vm.skipRemainingWarmups(modelContext: context)

        XCTAssertEqual(plan.orderedExercises[0].orderedSets.count, 2)
        XCTAssertEqual(vm.sessionState,
                       .exercise(.setActive(exerciseIndex: 0, setIndex: 0)))
    }
}
