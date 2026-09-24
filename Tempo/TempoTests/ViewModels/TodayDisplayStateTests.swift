//
// TodayDisplayStateTests.swift
// Tempo
//
// §16 — first launch / no plan showed "REST DAY": TodayWorkoutView checked
// `isRestDay` before `todayPlan == nil`, and `isRestDay` reads TRUE for both
// cases, so the "Generate Today's Workout" empty state was permanently
// unreachable. `todayDisplayState` is the single source the view now
// branches on — this pins that "no plan" and "a real rest day" are always
// told apart, in that priority order.
//

@testable import Tempo
import XCTest

@MainActor
final class TodayDisplayStateTests: XCTestCase {
    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    func testNoPlanIsNoPlanNotRestDay() {
        let vm = makeVM()
        vm.todayPlan = nil

        XCTAssertEqual(
            vm.todayDisplayState,
            .noPlan,
            "First launch / no plan must resolve to the empty state, not rest"
        )
        XCTAssertTrue(vm.isRestDay, "isRestDay itself is unchanged — still true for nil — only the VIEW's branch order changes")
    }

    func testRealRestDayIsRestDay() {
        let vm = makeVM()
        vm.todayPlan = WorkoutPlan(date: Date(), type: .rest)
        XCTAssertEqual(vm.todayDisplayState, .restDay)
    }

    func testMobilityDayIsRestDay() {
        let vm = makeVM()
        vm.todayPlan = WorkoutPlan(date: Date(), type: .mobility)
        XCTAssertEqual(vm.todayDisplayState, .restDay)
    }

    func testGymDayIsGym() {
        let vm = makeVM()
        vm.todayPlan = WorkoutPlan(date: Date(), type: .push)
        XCTAssertEqual(vm.todayDisplayState, .gym)
        XCTAssertTrue(vm.canStartWorkout)
    }

    func testNonGymDayIsNonGym() {
        let vm = makeVM()
        vm.todayPlan = WorkoutPlan(date: Date(), type: .football)
        XCTAssertEqual(vm.todayDisplayState, .nonGym)
        XCTAssertFalse(vm.canStartWorkout, "Non-gym days never show Start Workout")
    }
}
