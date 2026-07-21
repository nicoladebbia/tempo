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
        let container = try ModelContainer(for: WorkoutPlan.self, configurations: config)
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
