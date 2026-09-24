//
// NutritionTargetCalculatorTests.swift
// Tempo
//
// Bug B guard — the no-plan calorie/macro estimate. When today has no plan
// meals, the target is a TDEECalculator estimate (Mifflin + Katch + optional
// 7-day Whoop blend), NOT a crude hand-rolled 2687. These pin:
//   1. the hard fallback when there's no DietaryProfile at all,
//   2. that the no-Whoop path equals TDEECalculator's profile estimate,
//   3. that a Whoop average shifts the number the way the blend dictates,
//   4. that plan meals (when present) override the estimate entirely —
//      summing each meal's frozen plan baseline, never live totals the
//      rebalancer / substitutes rewrite, and never ad-hoc logs.
//

@testable import Tempo
import XCTest

final class NutritionTargetCalculatorTests: XCTestCase {
    private func profile() -> DietaryProfile {
        DietaryProfile(
            primaryGoal: .leanGain,
            bodyFatPercent: 14,
            currentWeightKg: 82,
            heightCm: 183,
            age: 22,
            biologicalSex: .male,
            trainingFrequency: 5
        )
    }

    // MARK: - 1. No profile → fixed hard fallback

    func testNoProfileNoMealsReturnsHardFallback() {
        let t = NutritionTargetCalculator.targetsForToday(
            todayMeals: [], dietaryProfile: nil
        )
        XCTAssertEqual(t.calories, 2400)
        XCTAssertEqual(t.protein, 180)
        XCTAssertEqual(t.carbs, 270)
        XCTAssertEqual(t.fat, 67)
    }

    // MARK: - 2. Profile, no Whoop → matches TDEECalculator estimate

    func testNoMealsProfileMatchesTDEECalculator() {
        let p = profile()
        let expected = TDEECalculator.calculate(
            weightKg: p.currentWeightKg, heightCm: p.heightCm, age: p.age,
            biologicalSex: p.biologicalSex, bodyFatPercent: p.bodyFatPercent,
            trainingFrequency: p.trainingFrequency, whoopAverageTDEE: nil,
            goal: p.primaryGoal
        )
        let t = NutritionTargetCalculator.targetsForToday(
            todayMeals: [], dietaryProfile: p, whoopAvgTDEE: nil
        )
        XCTAssertEqual(
            t.calories,
            expected.adjustedCalories,
            "No-plan estimate must equal TDEECalculator, not a crude inline Mifflin"
        )
        XCTAssertEqual(t.protein, expected.macroTargets.proteinGrams)
        XCTAssertEqual(t.carbs, expected.macroTargets.carbsGrams)
        XCTAssertEqual(t.fat, expected.macroTargets.fatGrams)
        // It must NOT be the old crude fallback for a real profile.
        XCTAssertNotEqual(t.calories, 2400)
    }

    // MARK: - 3. Whoop average flows through the blend

    func testWhoopAverageMatchesBlendedTDEECalculator() {
        let p = profile()
        let whoopAvg = 3100.0
        let expected = TDEECalculator.calculate(
            weightKg: p.currentWeightKg, heightCm: p.heightCm, age: p.age,
            biologicalSex: p.biologicalSex, bodyFatPercent: p.bodyFatPercent,
            trainingFrequency: p.trainingFrequency, whoopAverageTDEE: whoopAvg,
            goal: p.primaryGoal
        )
        let t = NutritionTargetCalculator.targetsForToday(
            todayMeals: [], dietaryProfile: p, whoopAvgTDEE: whoopAvg
        )
        XCTAssertEqual(
            t.calories,
            expected.adjustedCalories,
            "Whoop average must flow into TDEECalculator's 60/40 blend"
        )
    }

    func testWhoopAverageChangesTheNumber() {
        let p = profile()
        let withoutWhoop = NutritionTargetCalculator.targetsForToday(
            todayMeals: [], dietaryProfile: p, whoopAvgTDEE: nil
        )
        let withHighWhoop = NutritionTargetCalculator.targetsForToday(
            todayMeals: [], dietaryProfile: p, whoopAvgTDEE: 3600
        )
        XCTAssertNotEqual(
            withoutWhoop.calories,
            withHighWhoop.calories,
            "A meaningfully different Whoop average should move the estimate"
        )
    }

    // MARK: - 4. Plan meals override the estimate

    private func planMeal(kcal: Double, p: Double, c: Double, f: Double) -> PlannedMeal {
        PlannedMeal(
            dayDate: Date(), mealNumber: 1, mealName: "Breakfast",
            scheduledTime: "08:00", totalCalories: kcal, totalProtein: p,
            totalCarbs: c, totalFat: f,
            mealPlan: WeeklyMealPlan(startDate: Date(), endDate: Date())
        )
    }

    func testPlanMealsOverrideEstimateAndIgnoreWhoop() {
        let meal = planMeal(kcal: 800, p: 50, c: 80, f: 25)
        let t = NutritionTargetCalculator.targetsForToday(
            todayMeals: [meal], dietaryProfile: profile(), whoopAvgTDEE: 9999
        )
        XCTAssertEqual(t.calories, 800, "With plan meals, the target IS the meal sum")
        XCTAssertEqual(t.protein, 50)
        XCTAssertEqual(t.carbs, 80)
        XCTAssertEqual(t.fat, 25)
    }

    func testFrozenBaselineWinsOverRewrittenTotals() {
        // Rebalancer / substitute rewrote the meal after its baseline was
        // frozen — the target must stay the plan's allocation.
        let meal = planMeal(kcal: 800, p: 50, c: 80, f: 25)
        meal.capturePlanBaselineIfNeeded()
        meal.totalCalories = 1100
        meal.totalProtein = 70
        let t = NutritionTargetCalculator.targetsForToday(todayMeals: [meal], dietaryProfile: profile())
        XCTAssertEqual(t.calories, 800)
        XCTAssertEqual(t.protein, 50)
    }

    func testAdHocLogsDoNotRaiseThePlanTarget() {
        let planned = planMeal(kcal: 800, p: 50, c: 80, f: 25)
        let snack = planMeal(kcal: 300, p: 10, c: 30, f: 10)
        snack.markAsUnplannedLog()
        let t = NutritionTargetCalculator.targetsForToday(todayMeals: [planned, snack], dietaryProfile: profile())
        XCTAssertEqual(t.calories, 800, "An ad-hoc log adds to eaten, never to the target")
    }

    func testOnlyUnboundLogsFallBackToEstimate() {
        // Manual logs with no plan covering today → no plan allocation.
        let log = PlannedMeal(
            dayDate: Date(), mealNumber: 1, mealName: "Lunch", scheduledTime: "12:00",
            totalCalories: 600, totalProtein: 30, totalCarbs: 60, totalFat: 20, status: .eaten
        )
        let estimate = NutritionTargetCalculator.targetsForToday(todayMeals: [], dietaryProfile: profile())
        let t = NutritionTargetCalculator.targetsForToday(todayMeals: [log], dietaryProfile: profile())
        XCTAssertEqual(t, estimate)
    }

    func testApplyingCarryoverAddsOnlyWhenActive() {
        let base = NutritionTargetCalculator.Targets(calories: 2000, protein: 150, carbs: 200, fat: 60)
        let active = MacroCarryoverService.DailyAdjustment(
            calories: 150, protein: 10, carbs: 20, fat: 5, hasActiveCarryover: true
        )
        var inactive = active
        inactive.hasActiveCarryover = false
        XCTAssertEqual(
            NutritionTargetCalculator.applying(active, to: base),
            NutritionTargetCalculator.Targets(calories: 2150, protein: 160, carbs: 220, fat: 65)
        )
        XCTAssertEqual(NutritionTargetCalculator.applying(inactive, to: base), base)
    }
}
