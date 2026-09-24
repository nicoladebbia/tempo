//
// DashboardFuelDayTypeTests.swift
// Tempo
//
// T3 #4 — refreshBody() hardcoded `isTrainingDay: true, isRestDay: false`
// and only a follow-up refreshTrainingStatus() fixed it, which the
// .tempoNutritionLogged handler never called. So logging a meal on a rest
// day flipped the Dashboard back to a training-day target. These pin:
//   - the plan → Move status mapping,
//   - the Fuel target IS the canonical DailyNutritionTargets number,
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
        UserDefaults.standard.removeObject(forKey: HealthKitWorkoutDay.key)
        savedEnsurer = DailyResetCoordinator.workoutPlanEnsurer
        DailyResetCoordinator.workoutPlanEnsurer = nil
    }

    override func tearDown() async throws {
        DailyResetCoordinator.workoutPlanEnsurer = savedEnsurer
        UserDefaults.standard.removeObject(forKey: HealthKitWorkoutDay.key)
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Pure mapping

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

    // MARK: - Cross-surface: Dashboard == Nutrition Today

    /// The Fuel quadrant must show THE canonical target — the same
    /// `DailyNutritionTargets.today` Nutrition Today renders — including
    /// carryover, the rest-day cut and the weight-based hydration base.
    func testFuelTargetsEqualCanonicalDailyTarget() async throws {
        context.insert(WorkoutPlan(date: Date(), type: .rest))
        context.insert(DietaryProfile(currentWeightKg: 70))
        try context.save()

        let vm = DashboardViewModel(services: .mock())
        vm.setFuelContext(context)
        await vm.refresh(force: true)

        let canonical = DailyNutritionTargets.today(
            in: context,
            whoopAvgTDEE: vm.whoop.weeklyTDEEAverage,
            recoveryScore: vm.body.recoveryScore,
            strain: vm.body.strain
        )
        XCTAssertEqual(vm.fuel.calorieTarget, canonical.calories)
        XCTAssertEqual(vm.fuel.proteinTarget, canonical.protein)
        XCTAssertEqual(vm.fuel.carbsTarget, canonical.carbs)
        XCTAssertEqual(vm.fuel.fatTarget, canonical.fat)
        XCTAssertEqual(vm.fuel.adjustedTargets?.hydrationTargetMl, canonical.hydrationMl)
        XCTAssertTrue(canonical.day.isRestDay)
        XCTAssertEqual(canonical.day.bodyWeightKg, 70)
    }

    /// A HealthKit-only workout (mock HealthKit returns one) with no plan
    /// still makes today a training day — on the Dashboard AND in the
    /// canonical context Nutrition Today reads.
    func testHealthKitOnlyWorkoutCountsAsTrainingOnBothSurfaces() async throws {
        let vm = DashboardViewModel(services: .mock())
        vm.setFuelContext(context)
        await vm.refresh(force: true)

        XCTAssertTrue(vm.hasLoggedWorkoutToday)
        XCTAssertTrue(DailyNutritionTargets.dayContext(in: context).isTrainingDay)
        let canonical = DailyNutritionTargets.today(
            in: context,
            whoopAvgTDEE: vm.whoop.weeklyTDEEAverage,
            recoveryScore: vm.body.recoveryScore,
            strain: vm.body.strain
        )
        XCTAssertEqual(vm.fuel.calorieTarget, canonical.calories)
        XCTAssertEqual(vm.fuel.carbsTarget, canonical.carbs)
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
