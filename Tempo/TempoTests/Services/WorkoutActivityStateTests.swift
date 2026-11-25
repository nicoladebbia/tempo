//
// WorkoutActivityStateTests.swift
// Tempo
//
// The workout Live Activity's rest bar drains between `restStartedAt` and
// `restEndsAt`. The new field is optional, so a state written before it
// existed still decodes (and simply has no drain bar), and the range the
// widget hands to its system timer can never be inverted.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WorkoutActivityStateTests: XCTestCase {
    private typealias State = WorkoutActivityAttributes.ContentState

    private func state(
        resting: Bool = true,
        paused: Bool = false,
        start: Date? = nil,
        end: Date? = nil
    ) -> State {
        State(
            workoutType: "PUSH", exerciseName: "Bench Press", setText: "Set 1 of 3",
            completedSets: 1, totalSets: 9, isResting: resting, restEndsAt: end,
            restStartedAt: start, startedAt: nil, isPaused: paused
        )
    }

    func testTheDrainRangeRunsFromRestStartToRestEnd() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(90)
        let range = try XCTUnwrap(state(start: start, end: end).restDrainRange)
        XCTAssertEqual(range.lowerBound, start)
        XCTAssertEqual(range.upperBound, end)
    }

    func testNoDrainBarWithoutARunningRestOrWithoutBothEnds() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(90)
        XCTAssertNil(state(resting: false, start: start, end: end).restDrainRange)
        XCTAssertNil(state(paused: true, start: start, end: end).restDrainRange)
        XCTAssertNil(state(start: nil, end: end).restDrainRange, "an old state has no start: fall back to the session bar")
        XCTAssertNil(state(start: start, end: nil).restDrainRange)
    }

    func testTheRangeIsNeverInverted() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let range = try XCTUnwrap(state(start: start, end: start.addingTimeInterval(-30)).restDrainRange)
        XCTAssertLessThanOrEqual(range.lowerBound, range.upperBound, "a system timer range traps when inverted")
    }

    func testAStateWrittenBeforeTheFieldExistedStillDecodes() throws {
        let old = """
        {"workoutType":"PUSH","exerciseName":"Bench Press","setText":"Set 1 of 3","completedSets":1,\
        "totalSets":9,"isResting":true,"restEndsAt":0,"isPaused":false}
        """
        let decoded = try JSONDecoder().decode(State.self, from: Data(old.utf8))
        XCTAssertNil(decoded.restStartedAt)
        XCTAssertNil(decoded.restDrainRange)
    }

    func testTheStateRoundTripsWithItsRestStart() throws {
        let start = Date(timeIntervalSinceReferenceDate: 500)
        let original = state(start: start, end: start.addingTimeInterval(60))
        let copy = try JSONDecoder().decode(State.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(copy, original)
        XCTAssertEqual(copy.restStartedAt, start)
    }

    // MARK: - From the view model

    private func makeVM() throws -> (TrainingViewModel, ModelContext, WorkoutPlan) {
        let schema = Schema([
            WorkoutPlan.self, Exercise.self, PlannedExercise.self, PlannedSet.self,
            SetFeedback.self, PersonalRecord.self,
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let vm = TrainingViewModel(
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService()
        )
        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        let bench = Exercise(
            name: "Bench Press", muscleGroup: .chest, equipment: .barbell, movementPattern: .horizontalPush, isCompound: true
        )
        context.insert(bench)
        let slot = PlannedExercise(order: 0, workoutPlan: plan, exercise: bench)
        slot.sets = (1 ... 3).map { PlannedSet(setNumber: $0, targetReps: 8, targetWeight: 80, plannedExercise: slot) }
        try context.save()
        vm.todayPlan = plan
        return (vm, context, plan)
    }

    func testAnActiveRestCarriesWhenItStartedAndWhenItEnds() throws {
        let (vm, context, _) = try makeVM()
        vm.autoStartRest = true
        vm.currentExerciseIndex = 0
        vm.currentSetIndex = 0
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))
        vm.logSet(weight: 80, reps: 8, modelContext: context)

        let live = try XCTUnwrap(vm.liveActivityState())
        XCTAssertTrue(live.isResting)
        let end = try XCTUnwrap(live.restEndsAt)
        let start = try XCTUnwrap(live.restStartedAt)
        XCTAssertEqual(end.timeIntervalSince(start), vm.restTimerTotal, accuracy: 0.01, "the bar spans the whole rest")
        XCTAssertLessThanOrEqual(start, Date().addingTimeInterval(0.5))
        XCTAssertNotNil(live.restDrainRange)
        vm.stopRestTimer()
    }

    func testAStateOutsideARestHasNoRestStart() throws {
        let (vm, _, _) = try makeVM()
        vm.currentExerciseIndex = 0
        vm.currentSetIndex = 0
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))
        let live = try XCTUnwrap(vm.liveActivityState())
        XCTAssertFalse(live.isResting)
        XCTAssertNil(live.restStartedAt)
        XCTAssertNil(live.restEndsAt)
    }
}
