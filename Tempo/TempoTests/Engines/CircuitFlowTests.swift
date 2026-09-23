//
// CircuitFlowTests.swift
// Tempo
//
// Created by Tempo on 9/23/26.
//
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CircuitFlowTests: XCTestCase {
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

    /// A, B, C — a 3-exercise circuit (all sharing supersetGroup 1), each
    /// with `working` sets, plus an optional trailing independent exercise D.
    private func seedCircuit(working: Int, trailing: Bool = false, context: ModelContext) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)

        func makeExercise(_ name: String, order: Int) -> PlannedExercise {
            let ex = Exercise(
                name: name,
                muscleGroup: .chest,
                equipment: .dumbbell,
                movementPattern: .isolation,
                isCompound: false
            )
            context.insert(ex)
            let slot = PlannedExercise(order: order, supersetGroup: 1, workoutPlan: plan, exercise: ex)
            slot.sets = (1 ... working).map {
                PlannedSet(setNumber: $0, targetReps: 10, targetWeight: 20, plannedExercise: slot)
            }
            return slot
        }
        _ = makeExercise("A", order: 0)
        _ = makeExercise("B", order: 1)
        _ = makeExercise("C", order: 2)

        if trailing {
            let d = Exercise(
                name: "D",
                muscleGroup: .triceps,
                equipment: .cable,
                movementPattern: .isolation,
                isCompound: false
            )
            context.insert(d)
            let slotD = PlannedExercise(order: 3, workoutPlan: plan, exercise: d)
            slotD.sets = [PlannedSet(setNumber: 1, targetReps: 12, targetWeight: 15, plannedExercise: slotD)]
        }
        try? context.save()
        return plan
    }

    private func position(_ vm: TrainingViewModel) -> (ex: Int, set: Int) {
        (vm.currentExerciseIndex, vm.currentSetIndex)
    }

    // MARK: - Rotation

    func testCircuitMembersReturnsAllThreeInOrder() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedCircuit(working: 1, context: context)

        XCTAssertEqual(vm.circuitMembers(of: 0), [0, 1, 2])
        XCTAssertEqual(vm.circuitMembers(of: 1), [0, 1, 2])
        XCTAssertEqual(vm.circuitMembers(of: 2), [0, 1, 2])
    }

    func testFirstMemberRotatesToSecondWithNoRest() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedCircuit(working: 2, context: context)
        vm.autoStartRest = true // even ON, A1 → B1 takes none

        vm.logSet(weight: 20, reps: 10, modelContext: context)

        XCTAssertEqual(position(vm).ex, 1, "A1 flows straight into B")
        XCTAssertEqual(position(vm).set, 0)
        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 1, setIndex: 0)))
    }

    func testSecondMemberRotatesToThirdWithNoRest() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedCircuit(working: 2, context: context)

        vm.logSet(weight: 20, reps: 10, modelContext: context) // A1 → B
        vm.logSet(weight: 20, reps: 10, modelContext: context) // B1 → C

        XCTAssertEqual(position(vm).ex, 2, "B1 flows straight into C, no rest")
        XCTAssertEqual(position(vm).set, 0)
    }

    func testLastMemberOfRoundRestsThenReturnsToFirstWithWork() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedCircuit(working: 2, context: context)

        vm.logSet(weight: 20, reps: 10, modelContext: context) // A1 → B
        vm.logSet(weight: 20, reps: 10, modelContext: context) // B1 → C
        vm.logSet(weight: 20, reps: 10, modelContext: context) // C1 (round's last) → rest → A2

        XCTAssertEqual(position(vm).ex, 0, "The round's one shared rest leads back to A's next set")
        XCTAssertEqual(position(vm).set, 1)
    }

    func testFullCircuitEndsInSummary() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedCircuit(working: 1, context: context)

        vm.logSet(weight: 20, reps: 10, modelContext: context) // A1 → B1
        vm.logSet(weight: 20, reps: 10, modelContext: context) // B1 → C1
        vm.logSet(weight: 20, reps: 10, modelContext: context) // C1 — every member fully logged

        XCTAssertEqual(vm.sessionState, .summary)
    }

    func testFinishedCircuitAdvancesPastEveryMember() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedCircuit(working: 1, trailing: true, context: context)

        vm.logSet(weight: 20, reps: 10, modelContext: context) // A1 → B1
        vm.logSet(weight: 20, reps: 10, modelContext: context) // B1 → C1
        vm.logSet(weight: 20, reps: 10, modelContext: context) // C1 — circuit complete → D

        XCTAssertEqual(position(vm).ex, 3, "Advances to D, never lands back on a finished member")
        XCTAssertEqual(position(vm).set, 0)
    }

    func testUnevenCircuitMemberContinuesAloneWhenOthersAreDone() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        func makeExercise(_ name: String, order: Int, sets: Int) -> PlannedExercise {
            let ex = Exercise(
                name: name,
                muscleGroup: .chest,
                equipment: .dumbbell,
                movementPattern: .isolation,
                isCompound: false
            )
            context.insert(ex)
            let slot = PlannedExercise(order: order, supersetGroup: 1, workoutPlan: plan, exercise: ex)
            slot.sets = (1 ... sets).map {
                PlannedSet(setNumber: $0, targetReps: 10, targetWeight: 20, plannedExercise: slot)
            }
            return slot
        }
        let a = makeExercise("A", order: 0, sets: 3)
        _ = makeExercise("B", order: 1, sets: 1)
        _ = makeExercise("C", order: 2, sets: 1)
        try? context.save()
        vm.todayPlan = plan

        vm.logSet(weight: 20, reps: 10, modelContext: context) // A1 → B1
        vm.logSet(weight: 20, reps: 10, modelContext: context) // B1(done) → C1
        vm.logSet(weight: 20, reps: 10, modelContext: context) // C1(done), only A has work → A2 (normal flow)

        XCTAssertEqual(position(vm).ex, 0, "With B and C finished, A continues on its own — normal per-set flow")
        XCTAssertEqual(position(vm).set, 1)
        XCTAssertEqual(a.orderedSets.filter(\.completed).count, 1)
    }

    // MARK: - Manual group control (§6.5)

    private func seedThreeIndependentExercises(context: ModelContext) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        for (i, name) in ["A", "B", "C"].enumerated() {
            let ex = Exercise(
                name: name,
                muscleGroup: .chest,
                equipment: .dumbbell,
                movementPattern: .isolation,
                isCompound: false
            )
            context.insert(ex)
            let slot = PlannedExercise(order: i, workoutPlan: plan, exercise: ex)
            slot.sets = [PlannedSet(setNumber: 1, targetReps: 10, targetWeight: 20, plannedExercise: slot)]
        }
        try? context.save()
        return plan
    }

    func testGroupWithNextGrowsAPairIntoACircuit() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedThreeIndependentExercises(context: context)
        vm.todayPlan = plan
        let exercises = plan.orderedExercises

        vm.groupWithNext(exercises[0], modelContext: context) // A + B
        vm.groupWithNext(exercises[1], modelContext: context) // (A,B) + C

        XCTAssertEqual(vm.circuitMembers(of: 0), [0, 1, 2])
        XCTAssertEqual(exercises[0].supersetGroup, exercises[2].supersetGroup)
    }

    func testGroupWithNextIsNoOpAtTheEndOfThePlan() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedThreeIndependentExercises(context: context)
        vm.todayPlan = plan
        let last = plan.orderedExercises[2]

        vm.groupWithNext(last, modelContext: context)

        XCTAssertNil(last.supersetGroup)
    }

    func testBreakGroupSplitsTheMiddleExerciseOutOfACircuit() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedCircuit(working: 1, context: context)
        let exercises = try XCTUnwrap(vm.todayPlan?.orderedExercises)

        vm.breakGroup(exercises[1], modelContext: context)

        XCTAssertNil(exercises[1].supersetGroup)
        XCTAssertEqual(vm.circuitMembers(of: 0), [0], "A is now on its own")
        XCTAssertEqual(vm.circuitMembers(of: 2), [2], "C is now on its own")
    }

    func testBreakGroupOnUngroupedExerciseIsNoOp() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedThreeIndependentExercises(context: context)
        vm.todayPlan = plan

        vm.breakGroup(plan.orderedExercises[0], modelContext: context)

        XCTAssertNil(plan.orderedExercises[0].supersetGroup)
    }
}
