//
// EatenMealHistoryTests.swift
// Tempo
//
// Multi-day "meals eaten" (Progress Report, RecoverIQ context) must count
// canonical eaten PlannedMeals — including last weeks' meals that now live
// on ARCHIVED plans — never legacy MealLog, and never double-count a slot
// that was re-marked after a mid-day regeneration.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class EatenMealHistoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let cal = Calendar.current

    override func setUp() async throws {
        try await super.setUp()
        container = try TempoModelContainer.create(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private var today: Date {
        cal.startOfDay(for: Date())
    }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: today)!
    }

    private func plan(active: Bool) -> WeeklyMealPlan {
        let p = WeeklyMealPlan(startDate: day(-40), endDate: day(6), isActive: active)
        if !active {
            p.isArchived = true
        }
        context.insert(p)
        return p
    }

    @discardableResult
    private func meal(
        _ dayOffset: Int,
        number: Int = 1,
        status: MealStatus = .eaten,
        plan: WeeklyMealPlan? = nil,
        kcal: Double = 500
    ) -> PlannedMeal {
        let m = PlannedMeal(
            dayDate: day(dayOffset),
            mealNumber: number,
            totalCalories: kcal,
            totalProtein: 40,
            status: status,
            mealPlan: plan
        )
        context.insert(m)
        return m
    }

    private func fetchWindow(_ fromOffset: Int, _ toOffset: Int) -> [PlannedMeal] {
        EatenMealHistory.fetch(from: day(fromOffset), to: day(toOffset), in: context)
    }

    // MARK: - Tests

    func testCountsArchivedActiveAndUnboundEatenMeals() throws {
        let archived = plan(active: false)
        let active = plan(active: true)
        meal(-10, number: 1, plan: archived) // last week's plan, archived by a regen
        meal(-10, number: 2, plan: archived)
        meal(-1, number: 1, plan: active)
        meal(-3, number: 3) // Quick Log with no plan
        meal(0, number: 1, plan: active) // today
        try context.save()

        XCTAssertEqual(fetchWindow(-30, 1).count, 5)
    }

    func testIgnoresNonEatenStatusesAndLegacyMealLog() throws {
        let active = plan(active: true)
        meal(-2, number: 1, status: .planned, plan: active)
        meal(-2, number: 2, status: .skipped, plan: active)
        meal(-2, number: 3, status: .modified, plan: active)
        context.insert(MealLog(mealType: .lunch, loggedAt: day(-2), totalCalories: 500, dayDate: day(-2)))
        try context.save()

        XCTAssertEqual(fetchWindow(-30, 1).count, 0)
    }

    func testRespectsWindowBounds() throws {
        let active = plan(active: true)
        meal(-31, plan: active)
        meal(-30, plan: active)
        meal(1, plan: active) // tomorrow — outside [start, end)
        try context.save()

        XCTAssertEqual(fetchWindow(-30, 1).count, 1)
    }

    func testPastSlotReMarkedAfterRegenCountsOncePreferringActive() throws {
        let archived = plan(active: false)
        let active = plan(active: true)
        meal(-1, number: 2, plan: archived, kcal: 400)
        let kept = meal(-1, number: 2, plan: active, kcal: 650)
        meal(-1, number: 3, plan: archived) // different slot — counts
        try context.save()

        let result = fetchWindow(-1, 0)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.id == kept.id })
    }

    func testTodayUsesStrictActiveOrUnboundRule() throws {
        let archived = plan(active: false)
        let active = plan(active: true)
        meal(0, number: 1, plan: archived) // hidden on Dashboard/Today → not counted
        meal(0, number: 2, plan: active)
        meal(0, number: 5) // unbound
        try context.save()

        let result = fetchWindow(0, 1)
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains { $0.mealPlan?.isActive == false })
    }

    func testWeeklyRecapPromptReportsEatenPlannedMeals() throws {
        let archived = plan(active: false)
        meal(-3, number: 1, plan: archived, kcal: 600)
        meal(-2, number: 1, kcal: 400)
        try context.save()

        let meals = fetchWindow(-7, 0)
        let prompt = RecoveryAIInsightService.buildWeeklyPrompt(
            recoveries: [], meals: meals, exercises: [], runs: [], accountability: []
        )
        XCTAssertTrue(
            prompt.contains("Nutrition: logged on 2 days, total 1000 kcal, 80g protein"),
            prompt
        )
    }

    func testYesterdayContextReadsEatenPlannedMeals() throws {
        context.insert(DailyRecovery(date: day(-1), recoveryScore: 70))
        let archived = plan(active: false)
        meal(-1, number: 1, plan: archived, kcal: 700)
        meal(-1, number: 2, kcal: 300)
        meal(-1, number: 3, status: .planned, kcal: 999)
        try context.save()

        let service = RecoveryAIInsightService(apiClient: APIClient())
        let ctx = try XCTUnwrap(service.yesterdayContext(modelContext: context))
        XCTAssertEqual(ctx.mealCount, 2)
        XCTAssertEqual(ctx.mealCalories ?? 0, 1000, accuracy: 0.1)
        XCTAssertEqual(ctx.mealProtein ?? 0, 80, accuracy: 0.1)
    }
}
