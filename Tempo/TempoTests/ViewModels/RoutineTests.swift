//
// RoutineTests.swift
// Tempo
//
// My routines: saving keeps lifts / working sets / groups (not ramps or
// drops); applying swaps today's untouched gym plan for freshly prescribed
// lifts, and refuses non-gym or already-started days.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class RoutineTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try TempoModelContainer.create(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    private func exercise(_ name: String, compound: Bool = false) -> Exercise {
        let ex = Exercise(
            name: name,
            muscleGroup: .chest,
            equipment: .dumbbell,
            movementPattern: .isolation,
            isCompound: compound
        )
        context.insert(ex)
        return ex
    }

    private func plan(type: WorkoutType = .push, lifts: [(Exercise, Int, Int?)]) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: type)
        context.insert(plan)
        for (order, lift) in lifts.enumerated() {
            let slot = PlannedExercise(order: order, workoutPlan: plan, exercise: lift.0)
            slot.supersetGroup = lift.2
            var sets = [PlannedSet(setNumber: 1, targetReps: 10, targetWeight: 10, isWarmup: true, plannedExercise: slot)]
            sets += (0 ..< lift.1).map {
                PlannedSet(setNumber: $0 + 2, targetReps: 10, targetWeight: 20, plannedExercise: slot)
            }
            slot.sets = sets
        }
        try? context.save()
        return plan
    }

    func testSaveKeepsWorkingSetsAndGroups() throws {
        let a = exercise("Fly"), b = exercise("Raise"), c = exercise("Curl")
        let vm = makeVM()
        vm.todayPlan = plan(lifts: [(a, 3, 1), (b, 2, 1), (c, 4, nil)])

        let routine = try XCTUnwrap(vm.saveTodayAsRoutine(named: "  Upper A ", modelContext: context))

        XCTAssertEqual(routine.name, "Upper A")
        XCTAssertEqual(routine.items.map(\.exerciseName), ["Fly", "Raise", "Curl"])
        XCTAssertEqual(routine.items.map(\.workingSets), [3, 2, 4], "warmup ramps excluded")
        XCTAssertEqual(routine.items.map(\.group), [1, 1, nil])
    }

    func testSaveRejectsBlankName() {
        let vm = makeVM()
        vm.todayPlan = plan(lifts: [(exercise("Fly"), 3, nil)])
        XCTAssertNil(vm.saveTodayAsRoutine(named: "   ", modelContext: context))
    }

    func testApplyReplacesTodaysLiftsWithRoutine() throws {
        let old = exercise("Old Lift"), a = exercise("Fly"), b = exercise("Raise")
        let vm = makeVM()
        let today = plan(lifts: [(old, 3, nil)])
        vm.todayPlan = today
        let routine = WorkoutRoutine(name: "Mine", items: [
            RoutineItem(exerciseID: a.id, exerciseName: "Fly", workingSets: 4, group: 7),
            RoutineItem(exerciseID: b.id, exerciseName: "Raise", workingSets: 2, group: 7),
        ])
        context.insert(routine)

        XCTAssertTrue(vm.applyRoutine(routine, modelContext: context))

        let slots = today.orderedExercises
        XCTAssertEqual(slots.map { $0.exercise?.name }, ["Fly", "Raise"])
        XCTAssertEqual(slots.map { $0.orderedSets.filter { !$0.isWarmup }.count }, [4, 2])
        XCTAssertEqual(slots.map(\.supersetGroup), [7, 7])
        XCTAssertNotNil(routine.lastUsedAt)
    }

    func testApplyRefusesNonGymAndStartedDays() {
        let a = exercise("Fly")
        let routine = WorkoutRoutine(name: "Mine", items: [
            RoutineItem(exerciseID: a.id, exerciseName: "Fly", workingSets: 3),
        ])
        context.insert(routine)
        let vm = makeVM()

        vm.todayPlan = plan(type: .football, lifts: [])
        XCTAssertFalse(vm.applyRoutine(routine, modelContext: context))
        XCTAssertNotNil(vm.routineBlocker(for: vm.todayPlan))

        let started = plan(lifts: [(exercise("Other"), 3, nil)])
        started.status = .inProgress
        vm.todayPlan = started
        XCTAssertFalse(vm.applyRoutine(routine, modelContext: context))
        XCTAssertEqual(started.orderedExercises.first?.exercise?.name, "Other")
    }

    func testApplySkipsLiftsMissingFromLibrary() {
        let vm = makeVM()
        vm.todayPlan = plan(lifts: [(exercise("Old"), 3, nil)])
        let gone = WorkoutRoutine(name: "Gone", items: [
            RoutineItem(exerciseID: UUID(), exerciseName: "Deleted", workingSets: 3),
        ])
        context.insert(gone)
        XCTAssertFalse(vm.applyRoutine(gone, modelContext: context), "nothing resolvable → plan untouched")
        XCTAssertEqual(vm.todayPlan?.orderedExercises.first?.exercise?.name, "Old")
    }
}
