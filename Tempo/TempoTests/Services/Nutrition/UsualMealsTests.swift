//
// UsualMealsTests.swift
// Tempo
//
// "The usual" and "Same as yesterday": ranking over real logged history, and
// the Undo that takes back exactly what a one-tap log wrote.
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - UsualMealsRankingTests

final class UsualMealsRankingTests: XCTestCase {
    private let calendar = Calendar.current
    /// A Wednesday midday, so "yesterday" and "N days ago" are easy to read.
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12, minute: 30))!

    private func at(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func food(_ name: String, kcal: Double = 100) -> PlannedFood {
        PlannedFood(name: name, quantityGrams: 100, calories: kcal, proteinG: 10, carbsG: 10, fatG: 2)
    }

    private func entry(_ daysAgo: Int, _ hour: Int, _ type: MealType, _ names: [String]) -> UsualMeals.Entry {
        UsualMeals.Entry(eatenAt: at(daysAgo: daysAgo, hour: hour), type: type, foods: names.map { food($0) })
    }

    func testMostFrequentComesFirst() {
        let entries = [
            entry(1, 12, .lunch, ["rice", "chicken"]),
            entry(2, 12, .lunch, ["rice", "chicken"]),
            entry(3, 12, .lunch, ["rice", "chicken"]),
            entry(4, 12, .lunch, ["pasta"]),
            entry(5, 12, .lunch, ["pasta"]),
        ]
        let ranked = UsualMeals.ranked(entries, type: .lunch, now: now)
        XCTAssertEqual(ranked.map(\.days), [3, 2])
        XCTAssertEqual(ranked.first?.title, "Rice, chicken")
    }

    func testOnlyTheAskedMealType() {
        let entries = [
            entry(1, 8, .breakfast, ["oats"]), entry(2, 8, .breakfast, ["oats"]),
            entry(1, 12, .lunch, ["salad"]), entry(2, 12, .lunch, ["salad"]),
        ]
        XCTAssertEqual(UsualMeals.ranked(entries, type: .breakfast, now: now).map(\.title), ["Oats"])
        XCTAssertEqual(UsualMeals.ranked(entries, type: .lunch, now: now).map(\.title), ["Salad"])
        XCTAssertTrue(UsualMeals.ranked(entries, type: .dinner, now: now).isEmpty)
    }

    func testOneMealIsNotAHabit() {
        let entries = [entry(1, 12, .lunch, ["salad"]), entry(2, 12, .lunch, ["soup"])]
        XCTAssertTrue(UsualMeals.ranked(entries, type: .lunch, now: now).isEmpty)
    }

    func testTwiceOnTheSameDayCountsOnce() {
        let entries = [entry(1, 12, .snack, ["apple"]), entry(1, 16, .snack, ["apple"])]
        XCTAssertTrue(UsualMeals.ranked(entries, type: .snack, now: now).isEmpty)
    }

    func testFoodOrderAndCaseDoNotMatter() {
        let entries = [entry(1, 12, .lunch, ["Rice", "Chicken"]), entry(2, 12, .lunch, ["chicken", "rice"])]
        let ranked = UsualMeals.ranked(entries, type: .lunch, now: now)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.days, 2)
    }

    func testTodayDoesNotCountTowardsTheHabit() {
        let entries = [entry(0, 9, .lunch, ["salad"]), entry(1, 12, .lunch, ["salad"])]
        XCTAssertTrue(UsualMeals.ranked(entries, type: .lunch, now: now).isEmpty)
    }

    func testOlderThanTheWindowIsIgnored() {
        let old = UsualMeals.windowDays + 3
        let entries = [entry(old, 12, .lunch, ["salad"]), entry(old + 1, 12, .lunch, ["salad"])]
        XCTAssertTrue(UsualMeals.ranked(entries, type: .lunch, now: now).isEmpty)
    }

    func testTieGoesToTheMealEatenClosestToNowOfDay() {
        // Both eaten on two days. Now is 12:30: the 12:00 one is closer than 14:30.
        let entries = [
            entry(1, 14, .lunch, ["late wrap"]), entry(2, 15, .lunch, ["late wrap"]),
            entry(1, 12, .lunch, ["noon bowl"]), entry(2, 12, .lunch, ["noon bowl"]),
        ]
        let ranked = UsualMeals.ranked(entries, type: .lunch, at: now, now: now)
        XCTAssertEqual(ranked.map(\.title), ["Noon bowl", "Late wrap"])
    }

    func testLimitAndEmptyHistory() {
        XCTAssertTrue(UsualMeals.ranked([], type: .lunch, now: now).isEmpty)
        let entries = (1 ... 4).flatMap { index in
            [entry(1, 12, .lunch, ["meal \(index)"]), entry(2, 12, .lunch, ["meal \(index)"])]
        }
        XCTAssertEqual(UsualMeals.ranked(entries, type: .lunch, now: now, limit: 2).count, 2)
        XCTAssertTrue(UsualMeals.ranked(entries, type: .lunch, now: now, limit: 0).isEmpty)
    }

    func testUsualKeepsTheFoodsFromTheLastTimeAndTheirMacros() {
        let older = UsualMeals.Entry(eatenAt: at(daysAgo: 3, hour: 12), type: .lunch, foods: [food("rice", kcal: 200)])
        let newer = UsualMeals.Entry(eatenAt: at(daysAgo: 1, hour: 12), type: .lunch, foods: [food("rice", kcal: 260)])
        let usual = UsualMeals.ranked([older, newer], type: .lunch, now: now).first
        XCTAssertEqual(usual?.macros.calories, 260)
    }

    // MARK: Same as yesterday

    func testYesterdayCopiesYesterdaysMealOfTheSameType() {
        let entries = [
            entry(1, 8, .breakfast, ["oats", "banana"]),
            entry(1, 12, .lunch, ["salad"]),
            entry(2, 8, .breakfast, ["toast"]),
        ]
        let yesterday = UsualMeals.yesterday(entries, type: .breakfast, now: now)
        XCTAssertEqual(yesterday?.foods.map(\.name), ["oats", "banana"])
        XCTAssertEqual(UsualMeals.yesterday(entries, type: .lunch, now: now)?.foods.map(\.name), ["salad"])
    }

    func testYesterdayJoinsTwoLogsOfOneMealInOrder() {
        let entries = [entry(1, 8, .breakfast, ["toast"]), entry(1, 7, .breakfast, ["coffee"])]
        XCTAssertEqual(UsualMeals.yesterday(entries, type: .breakfast, now: now)?.foods.map(\.name), ["coffee", "toast"])
    }

    func testYesterdayIsAbsentWhenNothingWasLogged() {
        XCTAssertNil(UsualMeals.yesterday([], type: .lunch, now: now))
        XCTAssertNil(UsualMeals.yesterday([entry(2, 12, .lunch, ["salad"])], type: .lunch, now: now))
        XCTAssertNil(UsualMeals.yesterday([entry(0, 9, .lunch, ["salad"])], type: .lunch, now: now))
    }

    func testTitleIsShortForLongMeals() {
        XCTAssertEqual(UsualMeals.title(of: [food("oats")]), "Oats")
        XCTAssertEqual(UsualMeals.title(of: [food("oats"), food("milk"), food("banana"), food("honey")]), "Oats, milk and 2 more")
        XCTAssertEqual(UsualMeals.title(of: []), "Meal")
    }
}

// MARK: - UsualMealsHistoryTests

@MainActor
final class UsualMealsHistoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let calendar = Calendar.current

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = container.mainContext
    }

    private func log(daysAgo: Int, name: String, foods: [String], hour: Int = 12) throws {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        let eatenAt = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        let meal = PlannedMeal(
            dayDate: day, mealNumber: 1, mealName: name, scheduledTime: "12:00",
            foods: foods.map { PlannedFood(name: $0, quantityGrams: 100, calories: 100, proteinG: 5, carbsG: 10, fatG: 2) },
            totalCalories: Double(foods.count) * 100, status: .eaten, actualEatenAt: eatenAt
        )
        context.insert(meal)
        try context.save()
    }

    func testReadsRealEatenMealsAndRanksThem() throws {
        try log(daysAgo: 1, name: "Lunch", foods: ["rice", "chicken"])
        try log(daysAgo: 2, name: "Lunch", foods: ["rice", "chicken"])
        let entries = UsualMeals.entries(in: context)
        let ranked = UsualMeals.ranked(entries, type: .lunch)
        XCTAssertEqual(ranked.first?.days, 2)
        XCTAssertEqual(UsualMeals.yesterday(entries, type: .lunch)?.foods.count, 2)
    }

    func testSupplementDosesAndEmptyMealsAreNotMeals() throws {
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())))
        EatenMealRecorder.recordSupplementDose(
            name: "creatine", macros: .zero, takenAt: yesterday.addingTimeInterval(9 * 3600), day: yesterday, in: context
        )
        try context.save()
        try log(daysAgo: 2, name: "Lunch", foods: [])
        XCTAssertTrue(UsualMeals.entries(in: context).isEmpty)
    }

    func testNoHistoryMeansNothingToShow() {
        let entries = UsualMeals.entries(in: context)
        XCTAssertTrue(UsualMeals.ranked(entries, type: .lunch).isEmpty)
        XCTAssertNil(UsualMeals.yesterday(entries, type: .lunch))
    }
}

// MARK: - EatenMealUndoTests

@MainActor
final class EatenMealUndoTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = container.mainContext
    }

    private var env: MealOutcomeService.Env {
        MealOutcomeService.Env(modelContext: context, notifications: nil)
    }

    private func input(_ name: String, kcal: Double = 200, origin: MealOrigin? = nil) -> MealFoodItemInput {
        MealFoodItemInput(
            foodId: UUID().uuidString, name: name, brand: nil, servings: 1, servingSize: 100, servingUnit: "g",
            calories: kcal, proteinGrams: 10, carbsGrams: 20, fatGrams: 5, source: .manual, origin: origin
        )
    }

    private func eatenMeals() -> [PlannedMeal] {
        CanonicalMeals.eatenMeals(on: Date(), in: context)
    }

    func testUndoOfANewLogRemovesIt() throws {
        let result = try EatenMealRecorder.record(
            [input("toast")], type: .snack, eatenAt: Date(), source: .recentMeal, modelContext: context
        )
        XCTAssertNil(result.merged)
        XCTAssertEqual(eatenMeals().count, 1)
        XCTAssertTrue(try EatenMealRecorder.undoLog(result, env: env))
        XCTAssertTrue(eatenMeals().isEmpty)
    }

    func testUndoOfAMergeTakesBackOnlyTheNewFoods() throws {
        _ = try EatenMealRecorder.record(
            [input("eggs", kcal: 300)], type: .breakfast, eatenAt: Date(), source: .manual, modelContext: context
        )
        let second = try EatenMealRecorder.record(
            [input("toast", kcal: 150)], type: .breakfast, eatenAt: Date(), source: .recentMeal, modelContext: context
        )
        XCTAssertNotNil(second.merged, "the second breakfast log merges into the first")
        XCTAssertEqual(eatenMeals().count, 1)
        XCTAssertEqual(eatenMeals().first?.totalCalories, 450)

        XCTAssertTrue(try EatenMealRecorder.undoLog(second, env: env))
        let meal = try XCTUnwrap(eatenMeals().first, "the earlier foods stay")
        XCTAssertEqual(meal.foods.map(\.name), ["eggs"])
        XCTAssertEqual(meal.totalCalories, 300)
        XCTAssertEqual(meal.status, .eaten)
    }

    func testUndoOfAnEditPutsTheReplacedFoodBack() throws {
        _ = try EatenMealRecorder.record(
            [input("eggs", kcal: 300), input("toast", kcal: 100)], type: .breakfast, eatenAt: Date(),
            source: .manual, modelContext: context
        )
        let edit = try EatenMealRecorder.record(
            [input("eggs", kcal: 500)], type: .breakfast, eatenAt: Date(), source: .manual,
            resolution: .edit, modelContext: context
        )
        XCTAssertEqual(eatenMeals().first?.totalCalories, 600)
        XCTAssertTrue(try EatenMealRecorder.undoLog(edit, env: env))
        let meal = try XCTUnwrap(eatenMeals().first)
        XCTAssertEqual(meal.foods.map(\.name).sorted(), ["eggs", "toast"])
        XCTAssertEqual(meal.totalCalories, 400)
    }

    func testUndoOfAMergeRestoresTheLegacyLog() throws {
        let first = try EatenMealRecorder.record(
            [input("eggs")], type: .breakfast, eatenAt: Date(), source: .manual, modelContext: context
        )
        let logID = try XCTUnwrap(first.meal.linkedMealLogID)
        let second = try EatenMealRecorder.record(
            [input("toast")], type: .breakfast, eatenAt: Date(), source: .manual, modelContext: context
        )
        _ = try EatenMealRecorder.undoLog(second, env: env)
        var descriptor = FetchDescriptor<MealLog>(predicate: #Predicate<MealLog> { $0.id == logID })
        descriptor.fetchLimit = 1
        let log = try XCTUnwrap(context.fetch(descriptor).first)
        XCTAssertEqual(log.items.map(\.name), ["eggs"])
    }

    func testUndoDoesNothingWhenTheMealIsAlreadyGone() throws {
        let result = try EatenMealRecorder.record(
            [input("toast")], type: .snack, eatenAt: Date(), source: .manual, modelContext: context
        )
        try MealOutcomeService.undo(result.meal, env: env)
        XCTAssertFalse(try EatenMealRecorder.undoLog(result, env: env))
    }

    func testUndoOfAFilledPlanSlotGivesThePlannedDishBack() throws {
        let plan = WeeklyMealPlan(startDate: Date(), endDate: Date(), isActive: true)
        context.insert(plan)
        let slot = PlannedMeal(
            dayDate: Date(), mealNumber: 1, mealName: "Breakfast", scheduledTime: "08:00",
            foods: [PlannedFood(name: "planned oats", quantityGrams: 80, calories: 300, proteinG: 10, carbsG: 50, fatG: 6)],
            totalCalories: 300, totalProtein: 10, totalCarbs: 50, totalFat: 6, mealPlan: plan
        )
        context.insert(slot)
        try context.save()
        let result = try EatenMealRecorder.record(
            [input("eggs", kcal: 250)], type: .breakfast, eatenAt: Date(), source: .recentMeal, modelContext: context
        )
        XCTAssertEqual(result.meal.id, slot.id)
        XCTAssertEqual(slot.status, .eaten)
        XCTAssertTrue(try EatenMealRecorder.undoLog(result, env: env))
        XCTAssertEqual(slot.status, .planned)
        XCTAssertEqual(slot.foods.map(\.name), ["planned oats"])
    }
}

// MARK: - MealPresetPinTests

@MainActor
final class MealPresetPinTests: XCTestCase {
    func testNewPresetsAreNotPinnedAndPinSticks() throws {
        let container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let preset = MealPreset(name: "Oats", totalCalories: 300)
        context.insert(preset)
        try context.save()
        XCTAssertFalse(preset.isPinned)
        preset.isPinned = true
        try context.save()
        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<MealPreset>()).first)
        XCTAssertTrue(fetched.isPinned)
    }
}
