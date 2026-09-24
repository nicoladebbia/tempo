//
// EatenNutritionHistoryTests.swift
// Tempo
//
// Pins the real 7-day nutrition history that replaced the fake charts
// (DailyNutritionSummaryView used Int.random, FuelQuadrantDetailView a
// hardcoded array + "2,250 / 172g / 82%" weekly average):
//   - only EATEN PlannedMeals count (planned / skipped don't),
//   - today uses the canonical filter (active plan or unbound) so the bar
//     equals the Dashboard Fuel number; an archived plan's meal today is out,
//   - past days include archived plans (weekly regen archives history),
//   - days with nothing eaten are `hasData == false`, not a fake value.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class EatenNutritionHistoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let cal = Calendar.current

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PlannedMeal.self, WeeklyMealPlan.self, configurations: config)
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private var today: Date {
        cal.startOfDay(for: Date())
    }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: today)!
    }

    private func plan(active: Bool) -> WeeklyMealPlan {
        let p = WeeklyMealPlan(startDate: day(-6), endDate: day(6), isActive: active)
        p.isArchived = !active
        context.insert(p)
        return p
    }

    @discardableResult
    private func meal(
        on date: Date,
        kcal: Double,
        protein: Double = 0,
        status: MealStatus = .eaten,
        plan: WeeklyMealPlan? = nil
    ) -> PlannedMeal {
        let m = PlannedMeal(
            dayDate: date,
            totalCalories: kcal,
            totalProtein: protein,
            status: status,
            mealPlan: plan
        )
        context.insert(m)
        return m
    }

    func testReturnsSevenDaysOldestFirstEndingToday() {
        let history = EatenNutritionHistory.dailyTotals(in: context)
        XCTAssertEqual(history.count, 7)
        XCTAssertEqual(history.first?.date, day(-6))
        XCTAssertEqual(history.last?.date, today)
        XCTAssertTrue(history.allSatisfy { !$0.hasData }, "No meals → every day is 'no data', never a fake value")
    }

    func testOnlyEatenMealsCount() throws {
        let active = plan(active: true)
        meal(on: today, kcal: 600, protein: 40, plan: active)
        meal(on: today, kcal: 900, status: .planned, plan: active)
        meal(on: today, kcal: 500, status: .skipped, plan: active)
        meal(on: today, kcal: 300, protein: 20) // unbound quick log
        try context.save()

        let todayTotals = try XCTUnwrap(EatenNutritionHistory.dailyTotals(in: context).last)
        XCTAssertEqual(todayTotals.calories, 900)
        XCTAssertEqual(todayTotals.protein, 60)
        XCTAssertEqual(todayTotals.mealsEaten, 2)
        XCTAssertTrue(todayTotals.hasData)
    }

    func testTodayExcludesArchivedPlanButPastDaysIncludeIt() throws {
        let archived = plan(active: false)
        let active = plan(active: true)
        meal(on: today, kcal: 700, plan: archived) // stale duplicate after a regen
        meal(on: today, kcal: 800, plan: active)
        meal(on: day(-2), kcal: 2100, plan: archived) // last week's real history
        try context.save()

        let history = EatenNutritionHistory.dailyTotals(in: context)
        XCTAssertEqual(history.last?.calories, 800, "Today must match the Dashboard Fuel (active/unbound only)")
        XCTAssertEqual(history[4].date, day(-2))
        XCTAssertEqual(history[4].calories, 2100, "Archived plans hold past history and must still chart")
        XCTAssertFalse(history[5].hasData)
    }

    func testMealsOutsideWindowIgnored() throws {
        meal(on: day(-7), kcal: 1000)
        meal(on: day(1), kcal: 1000)
        try context.save()
        XCTAssertFalse(EatenNutritionHistory.dailyTotals(in: context).contains(where: \.hasData))
    }

    func testAveragesUseOnlyDaysWithData() throws {
        meal(on: day(-3), kcal: 2000, protein: 150)
        meal(on: day(-1), kcal: 2400, protein: 170)
        try context.save()

        let avg = try XCTUnwrap(EatenNutritionHistory.averages(of: EatenNutritionHistory.dailyTotals(in: context)))
        XCTAssertEqual(avg.calories, 2200)
        XCTAssertEqual(avg.protein, 160)
        XCTAssertEqual(avg.daysWithData, 2)
    }

    func testAveragesNilWithoutData() {
        XCTAssertNil(EatenNutritionHistory.averages(of: EatenNutritionHistory.dailyTotals(in: context)))
    }
}
