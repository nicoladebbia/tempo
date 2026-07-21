//
// TwoADayCompletionTests.swift
// Tempo
//
// Requirement (b), completion: the cardio SECOND session of a gym+cardio
// two-a-day is checked off independently of the lift. The DAY counts as trained
// on the lift's status; secondaryCompleted tracks the bonus cardio apart from
// it. Pins the toggle's model logic (the Today-card button that calls it is
// device-only to verify).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TwoADayCompletionTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutPlan.self, ActivitySession.self, configurations: config)
        return ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    func testMarkDoneFlipsTheSecondSessionFlag() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.secondarySessionType = .run
        context.insert(plan)
        vm.todayPlan = plan

        XCTAssertFalse(plan.secondaryCompleted, "Starts unchecked")
        vm.toggleSecondarySessionComplete(modelContext: context)
        XCTAssertTrue(plan.secondaryCompleted, "Mark done flips it on")
        vm.toggleSecondarySessionComplete(modelContext: context)
        XCTAssertFalse(plan.secondaryCompleted, "Undo flips it back off")
    }

    func testToggleNoOpsOnASingleSessionDay() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .legs) // no secondary session
        context.insert(plan)
        vm.todayPlan = plan

        vm.toggleSecondarySessionComplete(modelContext: context)
        XCTAssertFalse(plan.secondaryCompleted, "A day with no second session is never flagged complete")
    }

    func testMarkDoneLogsAManualActivitySessionForTheCardio() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.secondarySessionType = .run
        context.insert(plan)
        vm.todayPlan = plan

        vm.toggleSecondarySessionComplete(modelContext: context) // done
        let logged = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(logged.count, 1, "Marking the cardio done logs it as a real activity (feeds the (d) learner + load)")
        XCTAssertEqual(logged.first?.workoutType, WorkoutType.run.rawValue)
        XCTAssertEqual(logged.first?.source, "manual")

        vm.toggleSecondarySessionComplete(modelContext: context) // undo
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActivitySession>()).count, 0,
                       "Undo removes the logged cardio — flag and activity never disagree")
    }

    func testReDoneDoesNotDoubleLog() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .pull)
        plan.secondarySessionType = .pool
        context.insert(plan)
        vm.todayPlan = plan

        vm.toggleSecondarySessionComplete(modelContext: context) // done
        vm.toggleSecondarySessionComplete(modelContext: context) // undo
        vm.toggleSecondarySessionComplete(modelContext: context) // done again
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActivitySession>()).count, 1,
                       "Re-completing never accumulates duplicate activity rows")
    }

    func testCardioCompletionIsIndependentOfTheLift() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .pull)
        plan.secondarySessionType = .pool
        plan.status = .completed // the lift is done — the day counts as trained
        context.insert(plan)
        vm.todayPlan = plan

        XCTAssertFalse(plan.secondaryCompleted, "Finishing the lift does NOT auto-complete the cardio")
        vm.toggleSecondarySessionComplete(modelContext: context)
        XCTAssertTrue(plan.secondaryCompleted)
        XCTAssertEqual(plan.status, .completed, "Checking the cardio never touches the lift's status")
    }
}
