//
// WatchSyncTests.swift
// Tempo
//
// §21 — pins the phone half of real watch sync: the payload the wrist runs
// on (working sets only, targets from the next uncompleted set, nil off gym
// days) and applyWatchSetLog (completes the right set with the watch's
// actuals, flips planned → inProgress, no-ops on unknown exercises). The
// payload's dictionary bridge round-trips losslessly — it's the WCSession
// wire format.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WatchSyncTests: XCTestCase {
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
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    /// Bench (1 warmup + 3 working, first working completed) then Row (3 working).
    private func seedPlan(context: ModelContext, type: WorkoutType = .push) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: type)
        context.insert(plan)

        let bench = Exercise(name: "Bench Press", muscleGroup: .chest,
                             equipment: .barbell, movementPattern: .horizontalPush, isCompound: true)
        let row = Exercise(name: "Barbell Row", muscleGroup: .back,
                           equipment: .barbell, movementPattern: .horizontalPull, isCompound: true)
        context.insert(bench)
        context.insert(row)

        let benchSlot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        benchSlot.sets = [
            PlannedSet(setNumber: 1, targetReps: 8, targetWeight: 40, isWarmup: true, plannedExercise: benchSlot),
            PlannedSet(setNumber: 2, targetReps: 8, targetWeight: 80,
                       actualReps: 8, actualWeight: 80, completed: true, plannedExercise: benchSlot),
            PlannedSet(setNumber: 3, targetReps: 8, targetWeight: 82.5, plannedExercise: benchSlot),
            PlannedSet(setNumber: 4, targetReps: 8, targetWeight: 82.5, plannedExercise: benchSlot),
        ]

        let rowSlot = PlannedExercise(order: 1, workoutPlan: plan, exercise: row)
        rowSlot.sets = (1 ... 3).map {
            PlannedSet(setNumber: $0, targetReps: 10, targetWeight: 60, plannedExercise: rowSlot)
        }
        try? context.save()
        return plan
    }

    // MARK: - Payload wire format

    func testPayloadDictionaryRoundTrips() {
        let payload = WatchWorkoutPayload(
            workoutType: "PUSH",
            dayKey: "2026-07-27",
            exercises: [
                .init(name: "Bench Press", totalSets: 3, completedSets: 1,
                      targetReps: 8, targetWeightKg: 82.5),
            ],
            updatedAt: Date(timeIntervalSince1970: 1_753_600_000)
        )
        let decoded = WatchWorkoutPayload.from(dictionary: payload.toDictionary())
        XCTAssertEqual(decoded, payload, "The WCSession dictionary bridge must be lossless")
    }

    // MARK: - Payload builder

    func testPayloadCountsWorkingSetsOnlyAndTargetsNextUncompleted() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedPlan(context: context)

        let payload = try XCTUnwrap(vm.watchWorkoutPayload())
        XCTAssertEqual(payload.exercises.count, 2)

        let bench = payload.exercises[0]
        XCTAssertEqual(bench.totalSets, 3, "Warmup ramp never reaches the wrist")
        XCTAssertEqual(bench.completedSets, 1)
        XCTAssertEqual(bench.targetWeightKg, 82.5,
                       "Targets come from the NEXT uncompleted set, not the logged one")

        let row = payload.exercises[1]
        XCTAssertEqual(row.completedSets, 0)
        XCTAssertEqual(row.targetReps, 10)
    }

    func testPayloadNilOffGymDaysAndCompletedPlans() throws {
        let context = try makeContext()
        let vm = makeVM()

        XCTAssertNil(vm.watchWorkoutPayload(), "No plan → nothing to push")

        vm.todayPlan = seedPlan(context: context, type: .football)
        XCTAssertNil(vm.watchWorkoutPayload(), "Football day is not a wrist-loggable gym day")

        let plan = seedPlan(context: context)
        plan.status = .completed
        vm.todayPlan = plan
        XCTAssertNil(vm.watchWorkoutPayload(), "A finished day pushes nothing — watch shows done state")
    }

    // MARK: - Watch → phone set log

    func testWatchSetLogCompletesNextUncompletedWorkingSet() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = seedPlan(context: context)
        vm.todayPlan = plan

        let applied = vm.applyWatchSetLog(
            exerciseName: "Bench Press", reps: 7, weightKg: 85, modelContext: context
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(plan.status, .inProgress, "First wrist log opens the session")
        let benchSets = plan.orderedExercises[0].orderedSets
        XCTAssertFalse(benchSets[0].completed, "Warmup untouched")
        let logged = benchSets[2]
        XCTAssertTrue(logged.completed, "Set 3 is the next uncompleted working set")
        XCTAssertEqual(logged.actualReps, 7)
        XCTAssertEqual(logged.actualWeight, 85)
        XCTAssertFalse(benchSets[3].completed)
    }

    func testWatchSetLogFallsBackToTargetsWhenActualsMissing() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.todayPlan = seedPlan(context: context)

        XCTAssertTrue(vm.applyWatchSetLog(
            exerciseName: "Barbell Row", reps: nil, weightKg: nil, modelContext: context
        ))
        let logged = vm.todayPlan!.orderedExercises[1].orderedSets[0]
        XCTAssertEqual(logged.actualReps, 10, "Missing actuals default to the set's targets")
        XCTAssertEqual(logged.actualWeight, 60)
    }

    func testWatchSetLogNoOpsOnUnknownExerciseOrClosedPlan() throws {
        let context = try makeContext()
        let vm = makeVM()

        XCTAssertFalse(vm.applyWatchSetLog(
            exerciseName: "Bench Press", reps: 8, weightKg: 80, modelContext: context
        ), "No plan loaded → no-op")

        let plan = seedPlan(context: context)
        vm.todayPlan = plan
        XCTAssertFalse(vm.applyWatchSetLog(
            exerciseName: "Cable Fly", reps: 8, weightKg: 80, modelContext: context
        ), "Exercise not on today's plan → no-op")

        plan.status = .completed
        XCTAssertFalse(vm.applyWatchSetLog(
            exerciseName: "Bench Press", reps: 8, weightKg: 80, modelContext: context
        ), "Completed day rejects wrist logs")
    }
}
