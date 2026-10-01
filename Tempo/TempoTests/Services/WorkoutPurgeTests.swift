//
// WorkoutPurgeTests.swift
// Tempo
//
// Deleting a workout from History removes every record it produced — and
// only ITS records. The coach's DailySession is one per day (unique date),
// so it goes only with the plan it is linked to.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WorkoutPurgeTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        return ModelContext(container)
    }

    private func session(for plan: WorkoutPlan?, date: Date = Date()) -> DailySession {
        DailySession(
            date: date, modality: "strength", intensity: .moderate, durationMin: 45,
            blocksJSON: "[]", shortWhy: "test", floorTier: .normal, wasDowngraded: false,
            source: .brain, workoutPlan: plan
        )
    }

    private func loggedPlan(_ context: ModelContext, exercise: Exercise, coachSession: Bool) -> WorkoutPlan {
        let plan = WorkoutPlan(date: Date(), type: .push, status: .completed)
        context.insert(plan)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: exercise)
        let set = PlannedSet(setNumber: 1, targetReps: 5, targetWeight: 100, plannedExercise: slot)
        set.completed = true
        set.actualReps = 5
        set.actualWeight = 100
        slot.sets = [set]
        context.insert(SetFeedback(plannedSet: set, rpe: 8))
        context.insert(ExerciseHistory(date: Date(), estimated1RM: 116, workoutPlanID: plan.id, exercise: exercise))
        context.insert(PersonalRecord(type: .oneRepMax, value: 116, date: Date(), workoutPlanID: plan.id, exercise: exercise))
        context.insert(PredictionLog(
            exerciseID: exercise.id, workoutPlanID: plan.id,
            predictedWeight: 100, predictedReps: 5, signalUsedRaw: "test"
        ))
        if coachSession {
            context.insert(session(for: plan))
        }
        return plan
    }

    func testPurgeRemovesOnlyThatWorkoutsRecords() throws {
        let context = try makeContext()
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest, equipment: .barbell, movementPattern: .horizontalPush, isCompound: true)
        context.insert(bench)
        let doomed = loggedPlan(context, exercise: bench, coachSession: false)
        let kept = loggedPlan(context, exercise: bench, coachSession: true) // same day, same lift
        try context.save()
        let keptID = kept.id

        XCTAssertTrue(WorkoutPurge.purge(doomed, modelContext: context))

        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutPlan>()).map(\.id), [keptID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExerciseHistory>()).map(\.workoutPlanID), [keptID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersonalRecord>()).map(\.workoutPlanID), [keptID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<PredictionLog>()).map(\.workoutPlanID), [keptID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetFeedback>()).count, 1)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<DailySession>()).map(\.workoutPlanID), [keptID],
            "The day's coach session belongs to the other plan — it survives"
        )
    }

    func testPurgeRemovesTheWorkoutsOwnCoachSession() throws {
        let context = try makeContext()
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest, equipment: .barbell, movementPattern: .horizontalPush, isCompound: true)
        context.insert(bench)
        let doomed = loggedPlan(context, exercise: bench, coachSession: true)
        try context.save()

        XCTAssertTrue(WorkoutPurge.purge(doomed, modelContext: context))

        XCTAssertTrue(try context.fetch(FetchDescriptor<DailySession>()).isEmpty)
    }

    func testLegacyUnstampedSessionGoesOnlyWhenTheDayIsUnambiguous() {
        let only = WorkoutPlan(date: Date(), type: .push)
        let legacy = session(for: nil)
        XCTAssertEqual(
            WorkoutPurge.dailySessionsToDelete(for: only, allSessions: [legacy], allPlans: [only]).count, 1
        )
        let other = WorkoutPlan(date: Date(), type: .pull)
        XCTAssertTrue(
            WorkoutPurge.dailySessionsToDelete(for: only, allSessions: [legacy], allPlans: [only, other]).isEmpty,
            "Two plans that day — can't tell whose it is, so keep it"
        )
    }

    func testNewSessionsAreStampedWithTheirPlan() {
        let plan = WorkoutPlan(date: Date(), type: .push)
        XCTAssertEqual(session(for: plan).workoutPlanID, plan.id)
    }
}
