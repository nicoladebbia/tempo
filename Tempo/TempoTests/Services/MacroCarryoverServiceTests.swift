//
// MacroCarryoverServiceTests.swift
// Tempo
//
// §4 daily-adjust guard. The macro "carryover" was repurposed from a
// 5-day deficit spread into a CONSERVATIVE single-day refund + a
// missed-log gate. These pin the four behaviors the design hinges on:
//
//   1. PARTIAL MISSED LOG — logged breakfast + dinner, forgot lunch, so
//      intake looks like a fake ~half-day deficit AND a planned meal is
//      still unmarked. This is the exact case the OLD zero-logs-only
//      guard sailed past. Must fire onMissedLog and carry NOTHING.
//   2. REAL SMALL DEFICIT — a genuine, fully-marked under-eaten day
//      refunds onto exactly ONE next day, capped at maxRefundCalories.
//   3. SURPLUS — over-ate → never carried (only nudge up, never down).
//   4. ZERO LOGS — preserved original behavior: skip, no row.
//
// The target for the closed-out day is the sum of that day's plan
// baselines (NutritionTargetCalculator's plan branch) and intake is the
// canonical `.eaten` PlannedMeals — MealLog is no longer read. Each helper
// meal is bound to an active plan with a planned allocation (`calories`)
// and what was actually eaten (`ate`, defaults to the plan), so the
// arithmetic stays deterministic regardless of any DietaryProfile.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class MacroCarryoverServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var activePlan: WeeklyMealPlan!

    private let cal = Calendar.current

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: MacroCarryover.self, MealLog.self, PlannedMeal.self,
            WeeklyMealPlan.self, DietaryProfile.self,
            configurations: config
        )
        context = container.mainContext
        let today = cal.startOfDay(for: Date())
        activePlan = WeeklyMealPlan(
            startDate: cal.date(byAdding: .day, value: -3, to: today)!,
            endDate: cal.date(byAdding: .day, value: 3, to: today)!
        )
        context.insert(activePlan)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        activePlan = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private var yesterday: Date {
        cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
    }

    /// Insert a plan-bound meal for `day`: the plan allocated `calories`
    /// / `protein`; the user actually ate `ate` / `ateProtein` (default: as
    /// planned) when `status == .eaten`.
    @discardableResult
    private func plan(
        day: Date,
        number: Int,
        name: String,
        calories: Double,
        protein: Double = 0,
        ate: Double? = nil,
        ateProtein: Double? = nil,
        status: MealStatus = .eaten,
        in mealPlan: WeeklyMealPlan? = nil
    ) -> PlannedMeal {
        let meal = PlannedMeal(
            dayDate: day,
            mealNumber: number,
            mealName: name,
            scheduledTime: "08:00",
            totalCalories: calories,
            totalProtein: protein,
            totalCarbs: 0,
            totalFat: 0,
            mealPlan: mealPlan ?? activePlan
        )
        meal.capturePlanBaselineIfNeeded()
        meal.status = status
        if let ate {
            meal.totalCalories = ate
        }
        if let ateProtein {
            meal.totalProtein = ateProtein
        }
        context.insert(meal)
        return meal
    }

    private func activeRows() -> [MacroCarryover] {
        (try? context.fetch(FetchDescriptor<MacroCarryover>())) ?? []
    }

    // MARK: - 1. Partial missed log → notify, carry nothing

    func testPartialMissedLogFiresNotifierAndCarriesNothing() {
        // Target = 2000 kcal across three meals. User "logged" only
        // breakfast (600), forgot lunch + dinner → intake 600 < 0.5×2000
        // = 1000, and lunch/dinner remain .planned.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 600, status: .eaten)
        plan(day: yesterday, number: 2, name: "Lunch", calories: 700, status: .planned)
        plan(day: yesterday, number: 3, name: "Dinner", calories: 700, status: .planned)

        var fired = false
        MacroCarryoverService.captureCarryoverIfNeeded(
            for: yesterday, in: context, onMissedLog: { fired = true }
        )

        XCTAssertTrue(fired, "Partial implausible log must fire the missed-log notifier")
        XCTAssertTrue(
            activeRows().isEmpty,
            "A probable missed log must NOT create a refund row (no fake deficit)"
        )
    }

    // MARK: - 2. Real small deficit → capped single-day refund

    func testRealSmallDeficitCreatesCappedSingleDayRefund() throws {
        // Target 2000; all meals marked; logged 1700 → real 300 deficit.
        // No unmarked meal, intake 1700 > 1000 → not a missed log.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 700, status: .eaten)
        plan(day: yesterday, number: 2, name: "Lunch", calories: 700, ate: 400, status: .eaten)
        plan(day: yesterday, number: 3, name: "Dinner", calories: 600, status: .eaten)

        var fired = false
        MacroCarryoverService.captureCarryoverIfNeeded(
            for: yesterday, in: context, onMissedLog: { fired = true }
        )

        XCTAssertFalse(fired, "A fully-marked real deficit is not a missed log")
        let rows = activeRows()
        XCTAssertEqual(rows.count, 1, "A real deficit over threshold creates exactly one row")
        let row = try XCTUnwrap(rows.first)
        // 300 deficit > 150 cap → refund capped to 150.
        XCTAssertEqual(
            row.calories,
            MacroCarryoverService.maxRefundCalories,
            accuracy: 0.5,
            "Refund must be capped at maxRefundCalories"
        )
        XCTAssertEqual(row.spreadDays, 1, "Refund lands on a single day")
        // perDay share == full delta at spreadDays 1.
        XCTAssertEqual(row.perDayCalories, row.calories, accuracy: 0.001)
    }

    func testCappedDeficitScalesMacrosProportionally() throws {
        // NOTE: the un-capped calorie path is unreachable by design —
        // kcalThreshold (200) > maxRefundCalories (150), so any
        // calorie-driven deficit that clears the threshold is always
        // capped to exactly 150. This test therefore pins the CAPPED +
        // SCALED path (the only calorie path that exists): a 300-kcal /
        // 30-g deficit caps calories to 150 (scale 0.5) and protein to 15.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, protein: 60, status: .eaten)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, protein: 60, ate: 700, ateProtein: 30, status: .eaten)
        // Target 2000 kcal / 120 P. Logged 1700 / 90 → deficit 300 / 30.

        MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        let row = try XCTUnwrap(activeRows().first)
        // calorie deficit 300 capped to 150 → scale 0.5 → protein 30→15.
        let scale = MacroCarryoverService.maxRefundCalories / 300.0
        XCTAssertEqual(row.calories, 150, accuracy: 0.5)
        XCTAssertEqual(
            row.protein,
            30 * scale,
            accuracy: 0.5,
            "Macros scale by the same ratio as the capped calories"
        )
    }

    // MARK: - 3. Surplus → never carried

    func testSurplusIsNeverCarried() {
        // Target 2000; logged 2400 → 400 surplus. Must NOT create a row.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, ate: 1200, status: .eaten)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, ate: 1200, status: .eaten)

        MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        XCTAssertTrue(
            activeRows().isEmpty,
            "Over-eating is never subtracted from tomorrow (only nudge up)"
        )
    }

    // MARK: - 4. Zero logs → preserved skip

    func testZeroLogsSkipsAsBefore() {
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, status: .planned)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, status: .planned)

        var fired = false
        MacroCarryoverService.captureCarryoverIfNeeded(
            for: yesterday, in: context, onMissedLog: { fired = true }
        )
        XCTAssertTrue(activeRows().isEmpty, "Zero-log day creates no row (preserved)")
        XCTAssertFalse(
            fired,
            "Zero-log day is handled by the pre-existing empty-logs guard, not the missed-log notifier"
        )
    }

    // MARK: - 5. Sub-threshold deficit → no row

    func testSubThresholdDeficitCreatesNoRow() {
        // Target 2000; logged 1900 → 100 deficit < 200 threshold.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, status: .eaten)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, ate: 900, status: .eaten)

        MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        XCTAssertTrue(activeRows().isEmpty, "A deficit below threshold is noise — no row")
    }

    // MARK: - 6. Refund applies once then expires

    func testRefundExpiresAfterOneTick() {
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, status: .eaten)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, ate: 700, status: .eaten)

        MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        // Today the refund is active.
        let adjToday = MacroCarryoverService.activeAdjustmentForToday(in: context)
        XCTAssertTrue(adjToday.hasActiveCarryover)
        XCTAssertEqual(adjToday.calories, 150, accuracy: 0.5)

        // Next daily-reset tick: capturing a DIFFERENT (no-op) day still
        // ticks active rows. Today (the source) has no plan, so capture
        // for `today` ticks the existing row forward and expires it.
        let today = cal.startOfDay(for: Date())
        MacroCarryoverService.captureCarryoverIfNeeded(for: today, in: context)
        let adjAfter = MacroCarryoverService.activeAdjustmentForToday(in: context)
        XCTAssertFalse(
            adjAfter.hasActiveCarryover,
            "A single-day refund must expire after exactly one tick"
        )
    }

    // MARK: - 7. Not a missed log when intake is plausible despite unmarked meal

    func testPlausibleIntakeWithUnmarkedMealIsNotMissedLog() {
        // Target 2000; logged 1700 (> 1000 = 0.5×target) but dinner still
        // .planned. Plausible intake → NOT a missed log; treat as real
        // deficit and carry the capped refund.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 700, status: .eaten)
        plan(day: yesterday, number: 2, name: "Lunch", calories: 700, ate: 1000, status: .eaten)
        plan(day: yesterday, number: 3, name: "Dinner", calories: 600, status: .planned)

        var fired = false
        MacroCarryoverService.captureCarryoverIfNeeded(
            for: yesterday, in: context, onMissedLog: { fired = true }
        )
        XCTAssertFalse(
            fired,
            "Intake above the missed-log fraction is not a missed log even with an unmarked meal"
        )
        XCTAssertEqual(activeRows().count, 1, "Plausible real deficit still carries a capped refund")
    }

    // MARK: - 8. Mark-Eaten-only day (no MealLog at all) still carries

    func testMarkEatenOnlyDayWithSkippedMealCarriesRefund() throws {
        // The common path: Mark Eaten on breakfast, dinner skipped. Mark
        // Eaten writes no MealLog — the old MealLog-summing capture saw
        // "zero logs" and never carried. Canonical intake = 1000 of 2000.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, status: .eaten)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, status: .skipped)

        MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        XCTAssertTrue((try? context.fetch(FetchDescriptor<MealLog>()))?.isEmpty ?? false)
        let row = try XCTUnwrap(activeRows().first, "Canonical eaten PlannedMeals drive carryover")
        XCTAssertEqual(row.calories, MacroCarryoverService.maxRefundCalories, accuracy: 0.5)
    }

    // MARK: - 9. Ad-hoc logs never raise the target they're measured against

    func testUnplannedLogCountsAsIntakeNotTarget() {
        // Plan 2000; ate breakfast as planned + a 300 kcal ad-hoc snack,
        // skipped dinner → intake 1300, target stays 2000 → deficit 700.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, status: .eaten)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, status: .skipped)
        let snack = plan(day: yesterday, number: 4, name: "Snack", calories: 300, status: .eaten)
        snack.markAsUnplannedLog()

        MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        XCTAssertEqual(activeRows().count, 1)
    }

    func testDayWithOnlyUnboundLogsHasNoTarget() {
        // No plan covered the day — only manual logs. Nothing to compare to.
        let meal = PlannedMeal(
            dayDate: yesterday, mealNumber: 1, mealName: "Lunch", scheduledTime: "12:00",
            totalCalories: 400, totalProtein: 20, totalCarbs: 40, totalFat: 10, status: .eaten
        )
        context.insert(meal)

        MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        XCTAssertTrue(activeRows().isEmpty)
    }

    func testInactivePlanMealsAreIgnored() {
        // A superseded plan's rows for the same day must not count.
        let oldPlan = WeeklyMealPlan(startDate: yesterday, endDate: yesterday, isActive: false)
        context.insert(oldPlan)
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, status: .eaten)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, status: .eaten)
        plan(day: yesterday, number: 3, name: "Old", calories: 2000, status: .planned, in: oldPlan)

        MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        XCTAssertTrue(activeRows().isEmpty, "Old-plan allocation must not inflate the target")
    }
}
