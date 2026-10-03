//
// CanonicalMealReadersTests.swift
// Tempo
//
// DayPlannerService and the supplement scheduler read the same meals the Fuel
// screens do (CanonicalMeals): meals of an archived plan, or a slot that a
// rebuild replaced, are not counted.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CanonicalMealReadersTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let day = Calendar.current.startOfDay(for: Date())

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = container.mainContext
        let old = WeeklyMealPlan(startDate: day, endDate: day, isActive: false)
        let live = WeeklyMealPlan(startDate: day, endDate: day, isActive: true)
        context.insert(old)
        context.insert(live)
        // Slot 1 exists twice: the replaced one on the archived plan and the
        // live one. Slot 2 (archived only) is a removed meal.
        context.insert(PlannedMeal(dayDate: day, mealNumber: 1, mealName: "Old lunch", scheduledTime: "12:00", mealPlan: old))
        context.insert(PlannedMeal(dayDate: day, mealNumber: 1, mealName: "Lunch", scheduledTime: "13:00", mealPlan: live))
        context.insert(PlannedMeal(dayDate: day, mealNumber: 2, mealName: "Old dinner", scheduledTime: "19:00", mealPlan: old))
        try context.save()
    }

    func testDayPlannerIgnoresArchivedAndReplacedMeals() {
        let service = DayPlannerService(
            modelContext: context,
            calendar: MockCalendarService(),
            recoveryEngine: MockRecoveryEngine()
        )
        let blocks = service.fetchMeals(on: day)
        XCTAssertEqual(blocks.map(\.title), ["Lunch"])
    }

    func testSupplementContextIgnoresArchivedAndReplacedMeals() {
        let ctx = SupplementDayContext.build(date: day, modelContext: context)
        XCTAssertEqual(ctx.meals.map(\.mealName), ["Lunch"])
        XCTAssertEqual(ctx.meals.first?.minutes, 13 * 60)
    }

    func testHistoricalKeepsArchivedHistoryButCountsASlotOnce() throws {
        let past = Calendar.current.date(byAdding: .day, value: -2, to: day)!
        let old = WeeklyMealPlan(startDate: past, endDate: past, isActive: false)
        let live = WeeklyMealPlan(startDate: past, endDate: past, isActive: true)
        context.insert(old)
        context.insert(live)
        // Eaten only on the archived plan: real history, kept.
        context.insert(PlannedMeal(dayDate: past, mealNumber: 1, mealName: "Breakfast", status: .eaten, mealPlan: old))
        // Same slot on both plans: counted once, the active plan's row.
        context.insert(PlannedMeal(dayDate: past, mealNumber: 2, mealName: "Lunch", status: .eaten, mealPlan: old))
        context.insert(PlannedMeal(dayDate: past, mealNumber: 2, mealName: "Lunch", status: .planned, mealPlan: live))
        try context.save()
        let all = (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
        let result = CanonicalMeals.historical(all.filter { $0.dayDate == past })
        XCTAssertEqual(result.map(\.mealName).sorted(), ["Breakfast", "Lunch"])
        XCTAssertEqual(result.first { $0.mealName == "Lunch" }?.mealPlan?.isActive, true)
    }

    func testCoachBackwardWindowCountsReplacedSlotOnce() throws {
        let past = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        let old = WeeklyMealPlan(startDate: past, endDate: past, isActive: false)
        let live = WeeklyMealPlan(startDate: past, endDate: past, isActive: true)
        context.insert(old)
        context.insert(live)
        context.insert(PlannedMeal(dayDate: past, mealNumber: 1, mealName: "Lunch", status: .planned, mealPlan: old))
        context.insert(PlannedMeal(dayDate: past, mealNumber: 1, mealName: "Lunch", status: .planned, mealPlan: live))
        try context.save()
        let window = CoachContextAssembler.makeBackwardWindow(in: context, today: day, calendar: .current)
        XCTAssertEqual(window.first { $0.date == past }?.plannedMealCount, 1)
    }
}
