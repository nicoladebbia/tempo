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
// The target for the closed-out day is the sum of that day's
// PlannedMeal macros (NutritionTargetCalculator's plan branch), so the
// tests set the target directly via planned-meal macros and keep the
// arithmetic deterministic regardless of any DietaryProfile.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class MacroCarryoverServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

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
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private var yesterday: Date {
        cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
    }

    /// Insert a planned meal for `day` with the given macros + status.
    @discardableResult
    private func plan(
        day: Date,
        number: Int,
        name: String,
        calories: Double,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        status: MealStatus = .eaten
    ) -> PlannedMeal {
        let meal = PlannedMeal(
            dayDate: day,
            mealNumber: number,
            mealName: name,
            scheduledTime: "08:00",
            totalCalories: calories,
            totalProtein: protein,
            totalCarbs: carbs,
            totalFat: fat
        )
        meal.status = status
        context.insert(meal)
        return meal
    }

    /// Insert a MealLog for `day` with the given macros.
    private func log(
        day: Date,
        calories: Double,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0
    ) {
        let entry = MealLog(
            mealType: .lunch,
            totalCalories: calories,
            totalProtein: protein,
            totalCarbs: carbs,
            totalFat: fat,
            dayDate: cal.startOfDay(for: day)
        )
        context.insert(entry)
    }

    private func activeRows() -> [MacroCarryover] {
        (try? context.fetch(FetchDescriptor<MacroCarryover>())) ?? []
    }

    // MARK: - 1. Partial missed log → notify, carry nothing

    func testPartialMissedLogFiresNotifierAndCarriesNothing() throws {
        // Target = 2000 kcal across three meals. User "logged" only
        // breakfast (600), forgot lunch + dinner → intake 600 < 0.5×2000
        // = 1000, and lunch/dinner remain .planned.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 600, status: .eaten)
        plan(day: yesterday, number: 2, name: "Lunch", calories: 700, status: .planned)
        plan(day: yesterday, number: 3, name: "Dinner", calories: 700, status: .planned)
        log(day: yesterday, calories: 600)

        var fired = false
        MacroCarryoverService.captureCarryoverIfNeeded(
            for: yesterday, in: context, onMissedLog: { fired = true }
        )

        XCTAssertTrue(fired, "Partial implausible log must fire the missed-log notifier")
        XCTAssertTrue(activeRows().isEmpty,
                      "A probable missed log must NOT create a refund row (no fake deficit)")
    }

    // MARK: - 2. Real small deficit → capped single-day refund

    func testRealSmallDeficitCreatesCappedSingleDayRefund() throws {
        // Target 2000; all meals marked; logged 1700 → real 300 deficit.
        // No unmarked meal, intake 1700 > 1000 → not a missed log.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 700, status: .eaten)
        plan(day: yesterday, number: 2, name: "Lunch", calories: 700, status: .eaten)
        plan(day: yesterday, number: 3, name: "Dinner", calories: 600, status: .eaten)
        log(day: yesterday, calories: 1700)

        var fired = false
        MacroCarryoverService.captureCarryoverIfNeeded(
            for: yesterday, in: context, onMissedLog: { fired = true }
        )

        XCTAssertFalse(fired, "A fully-marked real deficit is not a missed log")
        let rows = activeRows()
        XCTAssertEqual(rows.count, 1, "A real deficit over threshold creates exactly one row")
        let row = try XCTUnwrap(rows.first)
        // 300 deficit > 150 cap → refund capped to 150.
        XCTAssertEqual(row.calories, MacroCarryoverService.maxRefundCalories, accuracy: 0.5,
                       "Refund must be capped at maxRefundCalories")
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
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, protein: 60, status: .eaten)
        // Target 2000 kcal / 120 P. Logged 1700 / 90 → deficit 300 / 30.
        log(day: yesterday, calories: 1700, protein: 90)

        MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        let row = try XCTUnwrap(activeRows().first)
        // calorie deficit 300 capped to 150 → scale 0.5 → protein 30→15.
        let scale = MacroCarryoverService.maxRefundCalories / 300.0
        XCTAssertEqual(row.calories, 150, accuracy: 0.5)
        XCTAssertEqual(row.protein, 30 * scale, accuracy: 0.5,
                       "Macros scale by the same ratio as the capped calories")
    }

    // MARK: - 3. Surplus → never carried

    func testSurplusIsNeverCarried() throws {
        // Target 2000; logged 2400 → 400 surplus. Must NOT create a row.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, status: .eaten)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, status: .eaten)
        log(day: yesterday, calories: 2400)

        MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        XCTAssertTrue(activeRows().isEmpty,
                      "Over-eating is never subtracted from tomorrow (only nudge up)")
    }

    // MARK: - 4. Zero logs → preserved skip

    func testZeroLogsSkipsAsBefore() throws {
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, status: .planned)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, status: .planned)
        // No MealLog inserted.

        var fired = false
        MacroCarryoverService.captureCarryoverIfNeeded(
            for: yesterday, in: context, onMissedLog: { fired = true }
        )
        XCTAssertTrue(activeRows().isEmpty, "Zero-log day creates no row (preserved)")
        XCTAssertFalse(fired,
                       "Zero-log day is handled by the pre-existing empty-logs guard, not the missed-log notifier")
    }

    // MARK: - 5. Sub-threshold deficit → no row

    func testSubThresholdDeficitCreatesNoRow() throws {
        // Target 2000; logged 1900 → 100 deficit < 200 threshold.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, status: .eaten)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, status: .eaten)
        log(day: yesterday, calories: 1900)

        MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        XCTAssertTrue(activeRows().isEmpty, "A deficit below threshold is noise — no row")
    }

    // MARK: - 6. Refund applies once then expires

    func testRefundExpiresAfterOneTick() throws {
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 1000, status: .eaten)
        plan(day: yesterday, number: 2, name: "Dinner", calories: 1000, status: .eaten)
        log(day: yesterday, calories: 1700) // 300 deficit → capped row

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
        XCTAssertFalse(adjAfter.hasActiveCarryover,
                       "A single-day refund must expire after exactly one tick")
    }

    // MARK: - 7. Not a missed log when intake is plausible despite unmarked meal

    func testPlausibleIntakeWithUnmarkedMealIsNotMissedLog() throws {
        // Target 2000; logged 1700 (> 1000 = 0.5×target) but dinner still
        // .planned. Plausible intake → NOT a missed log; treat as real
        // deficit and carry the capped refund.
        plan(day: yesterday, number: 1, name: "Breakfast", calories: 700, status: .eaten)
        plan(day: yesterday, number: 2, name: "Lunch", calories: 700, status: .eaten)
        plan(day: yesterday, number: 3, name: "Dinner", calories: 600, status: .planned)
        log(day: yesterday, calories: 1700)

        var fired = false
        MacroCarryoverService.captureCarryoverIfNeeded(
            for: yesterday, in: context, onMissedLog: { fired = true }
        )
        XCTAssertFalse(fired,
                       "Intake above the missed-log fraction is not a missed log even with an unmarked meal")
        XCTAssertEqual(activeRows().count, 1, "Plausible real deficit still carries a capped refund")
    }
}
