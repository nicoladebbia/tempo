//
// DashboardFuelDayTypeTests.swift
// Tempo
//
// T3 #4 — refreshBody() hardcoded `isTrainingDay: true, isRestDay: false`
// and only a follow-up refreshTrainingStatus() fixed it, which the
// .tempoNutritionLogged handler never called. So logging a meal on a rest
// day flipped the Dashboard back to a training-day target. These pin:
//   - the plan → flags mapping,
//   - refresh() ALONE produces the rest-day target on a rest day,
//   - refresh() and refreshTrainingStatus() agree (same number twice),
//   - the widget snapshot mirrors the Dashboard quadrants.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class DashboardFuelDayTypeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    /// The host app installs a real ensurer that regenerates today's plan
    /// (replacing the rest day under test) — isolate from it.
    private var savedEnsurer: (@MainActor (ModelContext) -> Void)?

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = container.mainContext
        WidgetSyncService.resetDedupe()
        savedEnsurer = DailyResetCoordinator.workoutPlanEnsurer
        DailyResetCoordinator.workoutPlanEnsurer = nil
    }

    override func tearDown() async throws {
        DailyResetCoordinator.workoutPlanEnsurer = savedEnsurer
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Pure mapping

    func testDayFlagsMapping() {
        XCTAssertEqual(
            DashboardViewModel.dayFlags(planStatus: .planned, hasLoggedWorkout: false),
            FuelDayFlags(isTrainingDay: true, isRestDay: false)
        )
        XCTAssertEqual(
            DashboardViewModel.dayFlags(planStatus: .completed, hasLoggedWorkout: false),
            FuelDayFlags(isTrainingDay: true, isRestDay: false)
        )
        XCTAssertEqual(
            DashboardViewModel.dayFlags(planStatus: .restDay, hasLoggedWorkout: true),
            FuelDayFlags(isTrainingDay: false, isRestDay: true),
            "A planned rest day stays a rest day"
        )
        XCTAssertEqual(
            DashboardViewModel.dayFlags(planStatus: DashboardWorkoutStatus.none, hasLoggedWorkout: false),
            FuelDayFlags(isTrainingDay: false, isRestDay: false),
            "Skipped with no logged workout → standard targets"
        )
        XCTAssertEqual(
            DashboardViewModel.dayFlags(planStatus: nil, hasLoggedWorkout: true),
            FuelDayFlags(isTrainingDay: true, isRestDay: false),
            "No plan but a HealthKit workout → training"
        )
        XCTAssertEqual(
            DashboardViewModel.dayFlags(planStatus: nil, hasLoggedWorkout: false),
            FuelDayFlags(isTrainingDay: false, isRestDay: false)
        )
    }

    func testWorkoutStatusMapping() {
        let today = Date()
        XCTAssertEqual(DashboardViewModel.dashboardWorkoutStatus(for: WorkoutPlan(date: today, type: .rest)), .restDay)
        XCTAssertEqual(DashboardViewModel.dashboardWorkoutStatus(for: WorkoutPlan(date: today, type: .push)), .planned)
        XCTAssertEqual(
            DashboardViewModel.dashboardWorkoutStatus(for: WorkoutPlan(date: today, type: .push, status: .inProgress)),
            .planned
        )
        XCTAssertEqual(
            DashboardViewModel.dashboardWorkoutStatus(for: WorkoutPlan(date: today, type: .legs, status: .completed)),
            .completed
        )
        XCTAssertEqual(
            DashboardViewModel.dashboardWorkoutStatus(for: WorkoutPlan(date: today, type: .legs, status: .skipped)),
            DashboardWorkoutStatus.none
        )
    }

    func testResolveDayFlagsReadsTodaysPlan() throws {
        context.insert(WorkoutPlan(date: Date(), type: .rest))
        try context.save()
        XCTAssertEqual(
            DashboardViewModel.resolveDayFlags(in: context, hasLoggedWorkout: false),
            FuelDayFlags(isTrainingDay: false, isRestDay: true)
        )
    }

    // MARK: - Refresh paths

    func testRefreshAloneAppliesRestDayTarget() async throws {
        context.insert(WorkoutPlan(date: Date(), type: .rest))
        try context.save()

        let vm = DashboardViewModel(services: .mock())
        vm.setFuelContext(context)
        await vm.refresh(force: true)

        let targets = try XCTUnwrap(vm.fuel.adjustedTargets)
        // Rest day never gets a training-day carb bump; with no red recovery
        // it's the −15% rest adjustment.
        if vm.body.recoveryZone != .red {
            XCTAssertEqual(targets.mode, .rest)
            XCTAssertEqual(targets.calorieTarget, Int(Double(targets.baseCalorieTarget) * 0.85))
        }
        XCTAssertNotEqual(targets.mode, .fuel, "Rest day must not be treated as a training day")
    }

    func testRefreshAndTrainingStatusAgree() async throws {
        context.insert(WorkoutPlan(date: Date(), type: .rest))
        try context.save()

        let vm = DashboardViewModel(services: .mock())
        vm.setFuelContext(context)
        await vm.refresh(force: true)
        let afterRefresh = vm.fuel.calorieTarget
        let carbsAfterRefresh = vm.fuel.carbsTarget

        vm.refreshTrainingStatus(modelContext: context)
        XCTAssertEqual(vm.fuel.calorieTarget, afterRefresh, "Both refresh paths must yield the same target")
        XCTAssertEqual(vm.fuel.carbsTarget, carbsAfterRefresh)
    }

    /// A forced refresh arriving while another refresh is in flight must not
    /// return until a pass that sees the new write has run — the
    /// .tempoNutritionLogged handler's follow-ups depend on it.
    func testForcedRefreshMidFlightSeesNewMeal() async throws {
        let vm = DashboardViewModel(services: .mock())
        vm.setFuelContext(context)

        let first = Task { await vm.refresh(force: true) }
        await Task.yield()
        context.insert(PlannedMeal(dayDate: Date(), totalCalories: 500, status: .eaten))
        try context.save()

        await vm.refresh(force: true)
        XCTAssertEqual(vm.fuel.caloriesConsumed, 500)
        await first.value
        XCTAssertEqual(vm.fuel.caloriesConsumed, 500)
    }

    // MARK: - Widget snapshot

    func testWidgetSnapshotMirrorsDashboard() {
        let vm = DashboardViewModel.preview()
        let snap = vm.widgetSnapshot
        XCTAssertEqual(snap.caloriesConsumed, vm.fuel.caloriesConsumed)
        XCTAssertEqual(snap.caloriesTarget, vm.fuel.calorieTarget)
        XCTAssertEqual(snap.protein, vm.fuel.proteinGrams)
        XCTAssertEqual(snap.carbs, vm.fuel.carbsGrams)
        XCTAssertEqual(snap.fat, vm.fuel.fatGrams)
        XCTAssertEqual(snap.mealsLogged, vm.fuel.mealsLogged)
        XCTAssertEqual(snap.mealsTarget, vm.fuel.mealsPlanned)
        XCTAssertEqual(snap.recoveryScore, 72)
        XCTAssertEqual(snap.recoveryZone, "green")
        XCTAssertEqual(snap.dailyScore, vm.dailyScore ?? 0)
        XCTAssertEqual(snap.nnTotal, vm.nonNegotiablesTotal)
        XCTAssertEqual(snap.nnCompleted, vm.nonNegotiablesDone)
    }
}
