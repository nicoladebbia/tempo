//
// EatenMealRecorderTests.swift
// Tempo
//
// The single "user ate these foods" write path (Quick Log, photo/barcode
// review, Log Meal sheet). Pins: it persists a canonical `.eaten`
// PlannedMeal (the bug: Log Meal saved nothing), fills the matching planned
// slot while freezing its plan baseline, merges add/edit into an eaten slot,
// cancels the filled slot's reminders and pings the Dashboard.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class EatenMealRecorderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: PlannedMeal.self, WeeklyMealPlan.self, MealLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func food(_ name: String, kcal: Double, p: Double = 10, c: Double = 20, f: Double = 5) -> MealFoodItemInput {
        MealFoodItemInput(
            foodId: UUID().uuidString, name: name, brand: nil, servings: 1,
            servingSize: 100, servingUnit: "g", calories: kcal,
            proteinGrams: p, carbsGrams: c, fatGrams: f, source: .manual
        )
    }

    private func activePlan() -> WeeklyMealPlan {
        let today = Calendar.current.startOfDay(for: Date())
        let plan = WeeklyMealPlan(
            startDate: Calendar.current.date(byAdding: .day, value: -1, to: today)!,
            endDate: Calendar.current.date(byAdding: .day, value: 5, to: today)!
        )
        context.insert(plan)
        return plan
    }

    @discardableResult
    private func plannedSlot(_ type: MealType, kcal: Double, in plan: WeeklyMealPlan, status: MealStatus = .planned) -> PlannedMeal {
        let meal = PlannedMeal(
            dayDate: Date(), mealNumber: type.sortOrder + 1, mealName: type.displayName,
            scheduledTime: "12:00",
            foods: [PlannedFood(name: "Planned dish", quantityGrams: 300, calories: kcal, proteinG: 40, carbsG: 60, fatG: 20)],
            totalCalories: kcal, totalProtein: 40, totalCarbs: 60, totalFat: 20,
            status: status, mealPlan: plan
        )
        context.insert(meal)
        return meal
    }

    private func allMeals() -> [PlannedMeal] {
        (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
    }

    // MARK: - Persists (item 1)

    func testRecordWithNoPlanPersistsUnboundEatenMealAndMealLog() throws {
        let result = try EatenMealRecorder.record(
            [food("Chicken", kcal: 300), food("Rice", kcal: 200)],
            type: .lunch, eatenAt: Date(), source: .manual, modelContext: context
        )
        let meals = allMeals()
        XCTAssertEqual(meals.count, 1, "Log Meal must persist a PlannedMeal")
        XCTAssertEqual(meals.first?.status, .eaten)
        XCTAssertNil(meals.first?.mealPlan)
        XCTAssertEqual(meals.first?.totalCalories, 500)
        XCTAssertEqual(meals.first?.planBaseline, .zero, "An ad-hoc log never raises the target")
        XCTAssertEqual(result.logged.calories, 500)
        XCTAssertEqual((try? context.fetch(FetchDescriptor<MealLog>()))?.count, 1)
        XCTAssertEqual(
            CanonicalMeals.eatenMeals(on: Date(), in: context).count,
            1,
            "The log is visible to every canonical reader"
        )
    }

    func testRecordWithoutMatchingSlotAttachesToActivePlanWithZeroBaseline() throws {
        let plan = activePlan()
        plannedSlot(.breakfast, kcal: 600, in: plan)
        let result = try EatenMealRecorder.record(
            [food("Bar", kcal: 250)], type: .snack, eatenAt: Date(), source: .manual, modelContext: context
        )
        XCTAssertTrue(result.meal.mealPlan === plan)
        XCTAssertEqual(result.meal.planBaseline, .zero)
        XCTAssertEqual(allMeals().count, 2)
    }

    func testRecordFillsPlannedSlotFreezesBaselineAndCancelsReminders() throws {
        let plan = activePlan()
        let slot = plannedSlot(.lunch, kcal: 700, in: plan)
        let notifications = MockNotificationService()
        notifications.scheduleOverdueMealReminder(
            mealID: slot.id, mealName: "Lunch", scheduledTime: Date().addingTimeInterval(3600), lateMinutes: 30
        )
        XCTAssertEqual(notifications.scheduledNotifications.count, 1)

        let posted = expectation(forNotification: .tempoNutritionLogged, object: nil)
        let result = try EatenMealRecorder.record(
            [food("Burrito", kcal: 900)], type: .lunch, eatenAt: Date(), source: .naturalLanguage,
            modelContext: context, notifications: notifications
        )
        wait(for: [posted], timeout: 1)

        XCTAssertTrue(result.meal === slot, "Fills the planned slot instead of adding a row")
        XCTAssertEqual(allMeals().count, 1)
        XCTAssertEqual(slot.status, .eaten)
        XCTAssertEqual(slot.totalCalories, 900)
        XCTAssertEqual(slot.foods.map(\.name), ["Burrito"])
        XCTAssertEqual(slot.planBaseline.calories, 700, "Target keeps the plan's allocation")
        XCTAssertNotNil(slot.linkedMealLogID)
        XCTAssertTrue(notifications.scheduledNotifications.isEmpty, "Overdue reminder cancelled")
    }

    func testAddAppendsAndEditReplacesSameNamedFoods() throws {
        let plan = activePlan()
        let slot = plannedSlot(.dinner, kcal: 800, in: plan)
        try EatenMealRecorder.record(
            [food("Pasta", kcal: 500)],
            type: .dinner,
            eatenAt: Date(),
            source: .manual,
            modelContext: context
        )
        XCTAssertEqual(
            EatenMealRecorder.duplicateNames(
                of: [food("pasta", kcal: 1)],
                type: .dinner,
                eatenAt: Date(),
                in: CanonicalMeals.meals(on: Date(), in: context)
            ),
            ["pasta"]
        )

        try EatenMealRecorder.record(
            [food("Pasta", kcal: 300)],
            type: .dinner,
            eatenAt: Date(),
            source: .manual,
            resolution: .add,
            modelContext: context
        )
        XCTAssertEqual(slot.foods.count, 2)
        XCTAssertEqual(slot.totalCalories, 800)

        try EatenMealRecorder.record(
            [food("Pasta", kcal: 450)],
            type: .dinner,
            eatenAt: Date(),
            source: .manual,
            resolution: .edit,
            modelContext: context
        )
        XCTAssertEqual(slot.foods.count, 1)
        XCTAssertEqual(slot.totalCalories, 450)
        XCTAssertEqual(slot.planBaseline.calories, 800, "Baseline frozen at the first fill")
    }

    func testDuplicateNamesEmptyWhenSlotNotYetEaten() {
        let plan = activePlan()
        plannedSlot(.lunch, kcal: 700, in: plan)
        XCTAssertTrue(EatenMealRecorder.duplicateNames(
            of: [food("Planned dish", kcal: 1)], type: .lunch, eatenAt: Date(),
            in: CanonicalMeals.meals(on: Date(), in: context)
        ).isEmpty)
    }

    func testInactivePlanSlotIsNotFilled() throws {
        let old = WeeklyMealPlan(startDate: Date(), endDate: Date(), isActive: false)
        context.insert(old)
        let stale = plannedSlot(.lunch, kcal: 700, in: old)
        try EatenMealRecorder.record(
            [food("Salad", kcal: 400)],
            type: .lunch,
            eatenAt: Date(),
            source: .manual,
            modelContext: context
        )
        XCTAssertEqual(stale.status, .planned)
        XCTAssertEqual(CanonicalMeals.eatenMeals(on: Date(), in: context).count, 1)
    }

    // MARK: - Helpers

    func testDefaultMealTypeByHour() {
        func at(_ hour: Int) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        }
        XCTAssertEqual(EatenMealRecorder.defaultMealType(for: at(7)), .breakfast)
        XCTAssertEqual(EatenMealRecorder.defaultMealType(for: at(12)), .lunch)
        XCTAssertEqual(EatenMealRecorder.defaultMealType(for: at(19)), .dinner)
        XCTAssertEqual(EatenMealRecorder.defaultMealType(for: at(23)), .snack)
    }
}
