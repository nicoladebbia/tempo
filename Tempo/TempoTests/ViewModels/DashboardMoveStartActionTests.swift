//
// DashboardMoveStartActionTests.swift
// Tempo
//
// The Move detail's primary button follows the Training tab: a gym day
// starts a workout, a rest / mobility day offers a mobility flow, and other
// non-gym days (football, run…) have nothing to start. It used to always
// say "Start Workout" and launch a gym session on a mobility day.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class DashboardMoveStartActionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var savedEnsurer: (@MainActor (ModelContext) -> Void)?

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = container.mainContext
        savedEnsurer = DailyResetCoordinator.workoutPlanEnsurer
        DailyResetCoordinator.workoutPlanEnsurer = nil
    }

    override func tearDown() async throws {
        DailyResetCoordinator.workoutPlanEnsurer = savedEnsurer
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func move(_ type: WorkoutType?) -> MoveQuadrantData {
        var data = MoveQuadrantData.empty
        data.workoutType = type
        return data
    }

    func testStartActionPerDayType() {
        XCTAssertEqual(move(.push).startAction, .workout)
        XCTAssertEqual(move(.fullBody).startAction, .workout)
        XCTAssertEqual(move(.mobility).startAction, .mobility)
        XCTAssertEqual(move(.rest).startAction, .mobility)
        XCTAssertEqual(move(.football).startAction, .none)
        XCTAssertEqual(move(nil).startAction, .workout, "Unknown day keeps the old button")
    }

    func testMobilityDayFlowsThroughToMoveAndQuickAction() throws {
        context.insert(WorkoutPlan(date: Date(), type: .mobility))
        try context.save()

        let vm = DashboardViewModel(services: .mock())
        vm.refreshTrainingStatus(modelContext: context)

        XCTAssertEqual(vm.move.workoutType, .mobility)
        XCTAssertEqual(vm.move.startAction, .mobility)
        let titles = vm.quickActions.map(\.title)
        XCTAssertTrue(titles.contains("Start a Mobility Flow"), "Got \(titles)")
        XCTAssertFalse(titles.contains { $0.hasSuffix("Workout") }, "Got \(titles)")
    }

    func testGymDayStillStartsWorkout() throws {
        context.insert(WorkoutPlan(date: Date(), type: .push))
        try context.save()

        let vm = DashboardViewModel(services: .mock())
        vm.refreshTrainingStatus(modelContext: context)

        XCTAssertEqual(vm.move.startAction, .workout)
        XCTAssertTrue(vm.quickActions.map(\.title).contains("Start Push Workout"))
    }
}
