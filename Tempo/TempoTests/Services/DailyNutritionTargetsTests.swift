//
// DailyNutritionTargetsTests.swift
// Tempo
//
// The canonical daily target: base + carryover, then NutritionEngine's
// recovery / rest-day adjustment, plus the note Nutrition Today shows.
// Also pins the day-context read and that the same-day rebalancer no
// longer compounds (target = frozen plan baseline, not live totals).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class DailyNutritionTargetsTests: XCTestCase {
    private let base = NutritionTargetCalculator.Targets(calories: 2000, protein: 150, carbs: 200, fat: 60)
    private let rest = DailyNutritionTargets.DayContext(isTrainingDay: false, isRestDay: true)
    private let training = DailyNutritionTargets.DayContext(isTrainingDay: true, isRestDay: false)

    /// Dashboard tests record the shared HealthKit-workout signal in
    /// UserDefaults.standard (the mock HealthKit returns a workout) — clear it
    /// so day-context expectations don't depend on test order.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: HealthKitWorkoutDay.key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: HealthKitWorkoutDay.key)
        super.tearDown()
    }

    // MARK: - Pure compute + note

    func testPlainDayEqualsBase() {
        let t = DailyNutritionTargets.compute(base: base, carryover: .zero, day: .unknown, recoveryScore: nil)
        XCTAssertEqual(t.targets, base)
        XCTAssertNil(t.note)
    }

    func testRestDayCut() {
        let t = DailyNutritionTargets.compute(base: base, carryover: .zero, day: rest, recoveryScore: nil)
        XCTAssertEqual(t.calories, 1700)
        XCTAssertEqual(t.carbs, 170)
        XCTAssertEqual(t.mode, .rest)
        XCTAssertEqual(t.note, "Rest day −15%")
    }

    func testRestDayCutSkippedWhenPlanCoversDay() {
        // A plan's rest day is already sized for rest, and the TDEE it
        // starts from is a weekly average — cutting it again undershoots.
        let t = DailyNutritionTargets.compute(
            base: base, carryover: .zero, day: rest, recoveryScore: nil, planCoversDay: true
        )
        XCTAssertEqual(t.targets, base)
        XCTAssertEqual(t.mode, .standard)
        XCTAssertNil(t.note)
        XCTAssertTrue(t.day.isRestDay, "The day is still a rest day for coaching")
    }

    func testRecoveryAdjustmentStillAppliesOnPlanRestDay() {
        let t = DailyNutritionTargets.compute(
            base: base, carryover: .zero, day: rest, recoveryScore: 20, planCoversDay: true
        )
        XCTAssertEqual(t.mode, .repair)
        XCTAssertEqual(t.calories, 2200)
    }

    func testGreenTrainingAddsCarbsAndTheirCalories() {
        let t = DailyNutritionTargets.compute(base: base, carryover: .zero, day: training, recoveryScore: 90)
        XCTAssertEqual(t.carbs, 240)
        XCTAssertEqual(t.calories, 2160)
        XCTAssertEqual(t.note, "Green recovery + training +20% carbs")
    }

    func testYellowTrainingCarbBumpAlsoRaisesCalories() {
        // Engine fix: the +10% carbs used to leave calories unchanged, so
        // kcal and macros disagreed.
        let t = DailyNutritionTargets.compute(base: base, carryover: .zero, day: training, recoveryScore: 50)
        XCTAssertEqual(t.carbs, 220)
        XCTAssertEqual(t.calories, 2080)
        XCTAssertEqual(t.note, "Yellow recovery + training +10% carbs")
    }

    func testCarryoverAppliedBeforeAdjustment() {
        let carry = MacroCarryoverService.DailyAdjustment(
            calories: 150, protein: 10, carbs: 20, fat: 0, hasActiveCarryover: true
        )
        let t = DailyNutritionTargets.compute(base: base, carryover: carry, day: .unknown, recoveryScore: nil)
        XCTAssertEqual(t.calories, 2150)
        XCTAssertEqual(t.beforeAdjustment.calories, 2150)
        XCTAssertEqual(t.base, base)
        XCTAssertEqual(t.note, "+150 kcal from yesterday")
    }

    // MARK: - Day context

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: WorkoutPlan.self, ActivitySession.self, PlannedMeal.self, WeeklyMealPlan.self,
            MacroCarryover.self, DietaryProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        retainedContainer = container
        return container.mainContext
    }

    private var retainedContainer: ModelContainer?

    func testDayContextUnknownWithoutPlanOrActivity() throws {
        XCTAssertEqual(try DailyNutritionTargets.dayContext(in: makeContext()), .unknown)
    }

    func testDayContextPlannedRestIsRestDay() throws {
        let ctx = try makeContext()
        ctx.insert(WorkoutPlan(date: Date(), type: .rest))
        let day = DailyNutritionTargets.dayContext(in: ctx)
        XCTAssertTrue(day.isRestDay)
        XCTAssertFalse(day.isTrainingDay)
    }

    func testDayContextLoggedActivityOverridesPlannedRest() throws {
        let ctx = try makeContext()
        ctx.insert(WorkoutPlan(date: Date(), type: .rest))
        ctx.insert(ActivitySession(
            date: Calendar.current.startOfDay(for: Date()), startTime: Date(), workoutType: "Soccer",
            sportID: 1, source: "manual", caloriesBurned: 600, durationMinutes: 90
        ))
        let day = DailyNutritionTargets.dayContext(in: ctx)
        XCTAssertTrue(day.isTrainingDay)
        XCTAssertFalse(day.isRestDay, "Played football → not a rest-day cut")
        XCTAssertEqual(day.activityCaloriesBurned, 600)
        XCTAssertEqual(day.activityDurationMin, 90)
    }

    func testHealthKitWorkoutMakesUnplannedDayTraining() throws {
        HealthKitWorkoutDay.record(true)
        let day = try DailyNutritionTargets.dayContext(in: makeContext())
        XCTAssertTrue(day.isTrainingDay, "Apple Watch run with no plan → training day")
        XCTAssertFalse(day.isRestDay)
    }

    func testHealthKitWorkoutDoesNotOverridePlannedRest() throws {
        HealthKitWorkoutDay.record(true)
        let ctx = try makeContext()
        ctx.insert(WorkoutPlan(date: Date(), type: .rest))
        let day = DailyNutritionTargets.dayContext(in: ctx)
        XCTAssertTrue(day.isRestDay)
        XCTAssertFalse(day.isTrainingDay)
    }

    func testHealthKitWorkoutSignalIsPerDay() throws {
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        HealthKitWorkoutDay.record(true, on: yesterday)
        XCTAssertFalse(HealthKitWorkoutDay.hasWorkout(on: Date()), "Yesterday's workout doesn't carry over")
        HealthKitWorkoutDay.record(true)
        XCTAssertTrue(HealthKitWorkoutDay.hasWorkout(on: Date()))
        HealthKitWorkoutDay.record(false)
        XCTAssertFalse(HealthKitWorkoutDay.hasWorkout(on: Date()), "Deleted workout clears today's signal")
    }

    func testDayContextPlannedGymSessionIsTraining() throws {
        let ctx = try makeContext()
        ctx.insert(WorkoutPlan(date: Date(), type: .push))
        XCTAssertEqual(DailyNutritionTargets.dayContext(in: ctx).isTrainingDay, true)
    }

    // MARK: - Rest day with / without a plan

    func testPlanRestDayKeepsPlanAllocation() throws {
        let ctx = try makeContext()
        ctx.insert(WorkoutPlan(date: Date(), type: .rest))
        let plan = WeeklyMealPlan(startDate: Date(), endDate: Date())
        ctx.insert(plan)
        ctx.insert(PlannedMeal(
            dayDate: Date(), mealNumber: 1, mealName: "Meal 1", scheduledTime: "12:00",
            totalCalories: 2000, totalProtein: 150, totalCarbs: 200, totalFat: 60, mealPlan: plan
        ))
        let t = DailyNutritionTargets.today(in: ctx, whoopAvgTDEE: nil, recoveryScore: nil)
        XCTAssertTrue(t.day.isRestDay)
        XCTAssertEqual(t.calories, 2000)
        XCTAssertEqual(t.carbs, 200)
        XCTAssertNil(t.note)
    }

    func testNoPlanRestDayStillCut() throws {
        let ctx = try makeContext()
        ctx.insert(WorkoutPlan(date: Date(), type: .rest))
        let t = DailyNutritionTargets.today(in: ctx, whoopAvgTDEE: nil, recoveryScore: nil)
        XCTAssertEqual(t.base.calories, 2400)
        XCTAssertEqual(t.calories, 2040)
        XCTAssertEqual(t.mode, .rest)
        XCTAssertEqual(t.note, "Rest day −15%")
    }

    // MARK: - No compounding

    func testTodayTargetIgnoresRebalancedTotals() throws {
        // Simulates the rebalancer rewriting remaining meals after a Mark
        // Eaten: the target must stay the plan's allocation so the next
        // rebalance doesn't re-apply the same adjustment on top.
        let ctx = try makeContext()
        let plan = WeeklyMealPlan(startDate: Date(), endDate: Date())
        ctx.insert(plan)
        var meals: [PlannedMeal] = []
        for n in 1 ... 2 {
            let meal = PlannedMeal(
                dayDate: Date(), mealNumber: n, mealName: "Meal \(n)", scheduledTime: "12:00",
                totalCalories: 1000, totalProtein: 75, totalCarbs: 100, totalFat: 30, mealPlan: plan
            )
            ctx.insert(meal)
            meals.append(meal)
        }
        let before = DailyNutritionTargets.today(in: ctx, whoopAvgTDEE: nil, recoveryScore: nil)
        for meal in meals {
            meal.capturePlanBaselineIfNeeded()
        }
        meals[1].totalCalories = 1400 // rebalanced up
        let after = DailyNutritionTargets.today(in: ctx, whoopAvgTDEE: nil, recoveryScore: nil)
        XCTAssertEqual(before.calories, 2000)
        XCTAssertEqual(after.calories, 2000, "Rebalanced totals must not feed back into the target")
    }
}
