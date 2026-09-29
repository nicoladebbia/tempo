//
// TrainingQAPolishTests.swift
// Tempo
//
// QA bugs G + H — a 1-set session reported "6 exercises"; the monthly
// debrief was offered on an empty month; the Dashboard said "Start" for a
// workout that was mid-session.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainingQAPolishTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        return ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    func testPerformedExerciseCountIgnoresUntouchedExercises() throws {
        let context = try makeContext()
        let plan = WorkoutPlan(date: Date(), type: .pull)
        context.insert(plan)
        for order in 0 ..< 3 {
            let slot = PlannedExercise(order: order, workoutPlan: plan, exercise: nil)
            slot.sets = [
                PlannedSet(setNumber: 1, targetReps: 8, targetWeight: 20, isWarmup: true, plannedExercise: slot),
                PlannedSet(setNumber: 2, targetReps: 8, targetWeight: 40, plannedExercise: slot),
            ]
            context.insert(slot)
        }
        try context.save()
        // Only a warm-up on #1, a working set on #2, nothing on #3.
        plan.orderedExercises[0].orderedSets[0].completed = true
        plan.orderedExercises[1].orderedSets[1].completed = true

        XCTAssertEqual(plan.performedExerciseCount, 1)
        XCTAssertEqual(plan.orderedExercises.count, 3)
    }

    private func septemberDay(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!
    }

    func testMonthlyDebriefNeedsARealMonth() throws {
        let context = try makeContext()
        let vm = makeVM()
        let now = septemberDay(29)

        for day in 1 ... 3 {
            let plan = WorkoutPlan(date: septemberDay(day * 5), type: .push)
            plan.status = .completed
            context.insert(plan)
        }
        try context.save()
        XCTAssertNil(vm.monthlyReviewDue(modelContext: context, now: now), "3 sessions isn't a month to debrief")

        let fourth = WorkoutPlan(date: septemberDay(20), type: .pull)
        fourth.status = .completed
        context.insert(fourth)
        try context.save()
        XCTAssertEqual(vm.monthlyReviewDue(modelContext: context, now: now), "2026-09")
    }

    func testDashboardSaysResumeForInProgressWorkout() {
        XCTAssertEqual(DashboardViewModel.workoutActionTitle(name: "Pull", inProgress: true), "Resume Pull Workout")
        XCTAssertEqual(DashboardViewModel.workoutActionTitle(name: "Pull", inProgress: false), "Start Pull Workout")
    }
}
