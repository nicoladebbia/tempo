//
// FuelTotalsTests.swift
// Tempo
//
// One source for the day's eaten totals and one for the water target: the Fuel
// hero, the Log tab header, the product page's "fits today" and the Today tile
// all read the same value.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class FuelTotalsTests: XCTestCase {
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

    private func eaten(_ number: Int, kcal: Double, p: Double, c: Double, f: Double) -> PlannedMeal {
        PlannedMeal(
            dayDate: Date(),
            mealNumber: number,
            mealName: "Meal \(number)",
            scheduledTime: "12:00",
            foods: [],
            totalCalories: kcal,
            totalProtein: p,
            totalCarbs: c,
            totalFat: f,
            status: .eaten
        )
    }

    /// Three meals of 100.4 kcal / 10.4 g protein each: truncating per meal
    /// gave 300 / 30, and the right sum (301.2 / 31.2) rounds to 301 / 31.
    func testRoundsOnceFromTheUnroundedSum() {
        let meals = (1 ... 3).map { eaten($0, kcal: 100.4, p: 10.4, c: 20.4, f: 5.4) }
        let totals = CanonicalMeals.roundedTotals(of: meals)
        XCTAssertEqual(totals, RoundedMacros(calories: 301, protein: 31, carbs: 61, fat: 16))
    }

    func testHalfRoundsUpOnTheSum() {
        let meals = [eaten(1, kcal: 100.5, p: 0.5, c: 0, f: 0), eaten(2, kcal: 100.5, p: 0.5, c: 0, f: 0)]
        let totals = CanonicalMeals.roundedTotals(of: meals)
        XCTAssertEqual(totals.calories, 201)
        XCTAssertEqual(totals.protein, 1)
    }

    func testEatenTotalsSkipMealsNotEaten() {
        let planned = eaten(2, kcal: 500, p: 40, c: 50, f: 10)
        planned.status = .planned
        let skipped = eaten(3, kcal: 400, p: 30, c: 40, f: 10)
        skipped.status = .skipped
        let totals = CanonicalMeals.eatenRoundedTotals(of: [eaten(1, kcal: 600.6, p: 20.2, c: 70.2, f: 15.2), planned, skipped])
        XCTAssertEqual(totals, RoundedMacros(calories: 601, protein: 20, carbs: 70, fat: 15))
    }

    func testNoMealsIsZero() {
        XCTAssertEqual(CanonicalMeals.roundedTotals(of: []), .zero)
    }

    /// The Fuel hero reads the view model; it must equal the shared total.
    func testFuelViewModelReadsTheSharedTotals() {
        let meals = (1 ... 3).map { eaten($0, kcal: 100.4, p: 10.4, c: 20.4, f: 5.4) }
        let viewModel = NutritionTabViewModel()
        viewModel._testSetTodayMeals(meals)
        XCTAssertEqual(viewModel.todayCaloriesConsumed, 301)
        XCTAssertEqual(viewModel.todayProteinConsumed, 31)
        XCTAssertEqual(viewModel.todayCarbsConsumed, 61)
        XCTAssertEqual(viewModel.todayFatConsumed, 16)
        XCTAssertEqual(viewModel.todayEatenTotals, CanonicalMeals.eatenRoundedTotals(of: meals))
    }

    /// The product page's "fits today" left-over is target minus what Fuel
    /// shows as eaten: the same whole number on both screens.
    func testProductPageRemainingMatchesFuel() throws {
        let meals = (1 ... 3).map { eaten($0, kcal: 100.4, p: 10.4, c: 20.4, f: 5.4) }
        for meal in meals {
            context.insert(meal)
        }
        try context.save()
        let targets = DailyNutritionTargets.today(in: context, whoopAvgTDEE: nil, recoveryScore: nil)
        let fit = FoodFitContext.load(in: context, targets: targets)
        let viewModel = NutritionTabViewModel()
        viewModel._testSetTodayMeals(meals)
        XCTAssertEqual(fit.remainingCalories, targets.calories - viewModel.todayCaloriesConsumed)
        XCTAssertEqual(fit.remainingProtein, targets.protein - viewModel.todayProteinConsumed)
    }

    func testWaterTargetIsTheTodayTilesTarget() {
        let expected = DailyNutritionTargets.today(
            in: context,
            whoopAvgTDEE: nil,
            recoveryScore: DailyNutritionTargets.storedRecoveryScore(in: context)
        ).hydrationMl
        XCTAssertEqual(DailyNutritionTargets.todayWaterTargetMl(in: context), expected)
        XCTAssertGreaterThan(expected, 0)
    }
}
