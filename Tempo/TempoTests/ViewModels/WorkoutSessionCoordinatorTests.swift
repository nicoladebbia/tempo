//
// WorkoutSessionCoordinatorTests.swift
// TempoTests
//
// One training session for the whole app: Today, the Train tab and the Move
// detail share it, a double tap on Start never starts twice, and a tap while
// a session is already running shows that session.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WorkoutSessionCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func makeCoordinator() -> WorkoutSessionCoordinator {
        ServiceContainer.mock().workoutSession
    }

    /// Makes today startable whatever the mock engine planned.
    private func makeTodayStartable(_ coordinator: WorkoutSessionCoordinator) async throws {
        await coordinator.prepare(modelContext: context).value
        let vm = coordinator.viewModel
        if vm.todayPlan == nil || vm.todayPlan?.type == .rest || vm.todayPlan?.orderedExercises.isEmpty == true {
            let plan = WorkoutPlan(date: Date(), type: .push)
            context.insert(plan)
            let bench = Exercise(name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
                                 movementPattern: .horizontalPush, isCompound: true)
            context.insert(bench)
            let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
            slot.sets = (1 ... 3).map { PlannedSet(setNumber: $0, targetReps: 8, targetWeight: 60, plannedExercise: slot) }
            try context.save()
            vm.todayPlan = plan
        }
        vm.todayPlan?.status = .planned
    }

    func testTheContainerOwnsOneSessionForEveryScreen() {
        let services = ServiceContainer.mock()
        XCTAssertTrue(services.workoutSession === services.workoutSession)
        XCTAssertTrue(services.workoutSession.viewModel === services.workoutSession.viewModel)
    }

    func testPrepareLoadsTodayOnce() async {
        let coordinator = makeCoordinator()
        let first = coordinator.prepare(modelContext: context)
        let second = coordinator.prepare(modelContext: context)
        XCTAssertEqual(first, second)
        await first.value
        XCTAssertTrue(coordinator.hasLoadedToday)
    }

    func testADoubleTapStartsOneSession() async throws {
        let coordinator = makeCoordinator()
        try await makeTodayStartable(coordinator)
        let context = try XCTUnwrap(context)

        let first = Task { @MainActor in await coordinator.start(modelContext: context) }
        let second = Task { @MainActor in await coordinator.start(modelContext: context) }
        let results = await [first.value, second.value]

        XCTAssertEqual(results.count(where: { $0 == .started }), 1, "\(results)")
        XCTAssertFalse(results.contains(.notStartable), "a second tap must never send the user to Train")
        XCTAssertEqual(coordinator.starts, 1)
        XCTAssertTrue(coordinator.showActiveWorkout)
        XCTAssertTrue(coordinator.viewModel.sessionState.isActive)
        coordinator.viewModel.resetState()
    }

    /// Started on Today, then Start tapped on Train: it is the same session.
    func testStartingAgainWhileRunningShowsTheRunningSession() async throws {
        let coordinator = makeCoordinator()
        try await makeTodayStartable(coordinator)
        let started = await coordinator.start(modelContext: context)
        XCTAssertEqual(started, .started)
        let state = coordinator.viewModel.sessionState

        coordinator.showActiveWorkout = false
        let again = await coordinator.start(modelContext: context)

        XCTAssertEqual(again, .alreadyRunning)
        XCTAssertTrue(coordinator.showActiveWorkout)
        XCTAssertEqual(coordinator.viewModel.sessionState, state)
        XCTAssertEqual(coordinator.starts, 1)
        coordinator.viewModel.resetState()
    }

    /// Started on the watch or recovered after a crash: no Start tap, but the
    /// session still needs its screen.
    func testASessionThatNeedsItsScreenGetsIt() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.showActiveWorkout)
        coordinator.sessionStateChanged(to: .crashedRecovery, modelContext: context)
        XCTAssertTrue(coordinator.showActiveWorkout)
        XCTAssertFalse(coordinator.showSummary)
    }
}
