//
// NutritionTabViewModelTests.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - Nutrition Tab ViewModel Tests

// Canonical daily targets, macro math sanity, meal-reminder scheduling.

@MainActor
final class NutritionTabViewModelTests: XCTestCase {
    private var viewModel: NutritionTabViewModel!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self,
            MealFeedback.self, PantryItem.self, SupplementIntakeLog.self,
            MealLog.self, MacroCarryover.self, WorkoutPlan.self, ActivitySession.self,
            TrainerProgram.self, UserSettings.self,
            configurations: config
        )
        viewModel = NutritionTabViewModel()
    }

    // MARK: - Macro Math (P×4 + C×4 + F×9 ≈ kcal)

    func testMacroMath_planning_sumsWithin10kcal() {
        // P×4 + C×4 + F×9 = 160 + 200 + 135 = 495 kcal
        viewModel._testSetTodayMeals([
            makePlanned(meal: 1, p: 40, c: 50, f: 15, kcal: 495, status: .eaten),
        ])
        let computed = viewModel.todayProteinConsumed * 4
            + viewModel.todayCarbsConsumed * 4
            + viewModel.todayFatConsumed * 9
        XCTAssertLessThanOrEqual(abs(computed - viewModel.todayCaloriesConsumed), 10)
    }

    // MARK: - Canonical daily target (base + carryover + recovery/rest)

    /// Two plan-bound meals totalling 2000 kcal / 150 P / 200 C / 60 F.
    private func seedPlannedDay() {
        let plan = WeeklyMealPlan(startDate: Date(), endDate: Date())
        let meals = [
            makePlanned(meal: 1, p: 75, c: 100, f: 30, kcal: 1000, status: .planned),
            makePlanned(meal: 2, p: 75, c: 100, f: 30, kcal: 1000, status: .planned),
        ]
        for meal in meals {
            meal.mealPlan = plan
        }
        viewModel._testSetTodayMeals(meals)
    }

    func testTodayTargets_plainDayIsPlanBaselineWithNoNote() {
        seedPlannedDay()
        viewModel._testSetTodayRecovery(nil)
        viewModel._testSetTargetInputs(carryover: .zero, day: .unknown)
        XCTAssertEqual(viewModel.todayCalorieTarget, 2000)
        XCTAssertEqual(viewModel.todayCarbsTarget, 200)
        XCTAssertNil(viewModel.todayTargetNote)
    }

    func testTodayTargets_restDayCutsFifteenPercentWithNote() {
        seedPlannedDay()
        viewModel._testSetTodayRecovery(nil)
        viewModel._testSetTargetInputs(
            carryover: .zero,
            day: DailyNutritionTargets.DayContext(isTrainingDay: false, isRestDay: true)
        )
        XCTAssertEqual(viewModel.todayCalorieTarget, 1700)
        XCTAssertEqual(viewModel.todayCarbsTarget, 170)
        XCTAssertEqual(viewModel.todayTargetNote, "Rest day −15%")
    }

    func testTodayTargets_redRecoveryAddsCaloriesAndProtein() {
        seedPlannedDay()
        viewModel._testSetTodayRecovery(WhoopRecoveryData(
            score: 20, hrvRmssd: 30, restingHeartRate: 70,
            spo2: 96, skinTemp: 33.0, date: Date()
        ))
        viewModel._testSetTargetInputs(carryover: .zero, day: .unknown)
        XCTAssertEqual(viewModel.todayCalorieTarget, 2200)
        XCTAssertEqual(viewModel.todayProteinTarget, 172)
        XCTAssertEqual(viewModel.todayTargetNote, "Red recovery +10% kcal, +15% protein")
    }

    func testTodayTargets_carryoverAddsBeforeAdjustmentAndShowsInNote() {
        seedPlannedDay()
        viewModel._testSetTodayRecovery(nil)
        viewModel._testSetTargetInputs(
            carryover: MacroCarryoverService.DailyAdjustment(
                calories: 150, protein: 0, carbs: 0, fat: 0, hasActiveCarryover: true
            ),
            day: DailyNutritionTargets.DayContext(isTrainingDay: false, isRestDay: true)
        )
        // (2000 + 150) × 0.85 = 1827.5 → 1827
        XCTAssertEqual(viewModel.todayCalorieTarget, 1827)
        XCTAssertEqual(viewModel.todayTargetNote, "Rest day −15% · +150 kcal from yesterday")
    }

    func testTodayTargets_matchFetchingTwinUsedByRebalancer() throws {
        // The ring (cached inputs) and the rebalancer (DailyNutritionTargets.today)
        // must produce the same number from the same store.
        let ctx = container.mainContext
        let plan = WeeklyMealPlan(startDate: Date(), endDate: Date())
        ctx.insert(plan)
        for n in 1 ... 2 {
            let meal = makePlanned(meal: n, p: 75, c: 100, f: 30, kcal: 1000, status: .planned)
            meal.mealPlan = plan
            ctx.insert(meal)
        }
        try ctx.save()
        viewModel.loadToday(modelContext: ctx)
        let fetched = DailyNutritionTargets.today(in: ctx, whoopAvgTDEE: nil, recoveryScore: nil)
        XCTAssertEqual(viewModel.todayTargets, fetched)
        XCTAssertEqual(fetched.calories, 2000)
    }

    // MARK: - Preset logging order

    func testLogFromPreset_insertsInChronologicalOrder() throws {
        let ctx = container.mainContext
        viewModel._testSetTodayMeals([
            makePlanned(meal: 1, p: 0, c: 0, f: 0, kcal: 0, status: .planned, scheduled: "00:00"),
            makePlanned(meal: 2, p: 0, c: 0, f: 0, kcal: 0, status: .planned, scheduled: "23:59"),
        ])
        let preset = MealPreset(name: "Oats", mealType: .breakfast)
        ctx.insert(preset)
        viewModel.logFromPreset(preset, modelContext: ctx)
        let names = viewModel.todayMeals.map(\.scheduledTime)
        XCTAssertEqual(viewModel.todayMeals.count, 3)
        XCTAssertEqual(names.first, "00:00")
        XCTAssertEqual(names.last, "23:59", "The preset (logged now) must land between, not at the end")
        let logged = try XCTUnwrap(viewModel.todayMeals.first { $0.mealName == MealType.breakfast.displayName })
        XCTAssertEqual(logged.planBaseline, .zero, "A preset log never raises the target")
        XCTAssertNotNil(logged.actualEatenAt)
    }

    func testChronological_sortsByTimeThenMealNumberMalformedLast() {
        let meals = [
            makePlanned(meal: 3, p: 0, c: 0, f: 0, kcal: 0, status: .planned, scheduled: "bad"),
            makePlanned(meal: 2, p: 0, c: 0, f: 0, kcal: 0, status: .planned, scheduled: "12:30"),
            makePlanned(meal: 1, p: 0, c: 0, f: 0, kcal: 0, status: .planned, scheduled: "12:30"),
            makePlanned(meal: 4, p: 0, c: 0, f: 0, kcal: 0, status: .planned, scheduled: "07:05"),
        ]
        XCTAssertEqual(NutritionTabViewModel.chronological(meals).map(\.mealNumber), [4, 1, 2, 3])
    }

    // MARK: - Meal Reminder Scheduling

    func testScheduleMealReminders_skipsAlreadyEaten() throws {
        try skipNearMidnight()
        let mock = MockNotificationService()
        viewModel._testSetTodayMeals([
            makePlanned(
                meal: 1,
                p: 30,
                c: 40,
                f: 10,
                kcal: 370,
                status: .eaten,
                scheduled: nextTimeString(addingMinutes: 30)
            ),
            makePlanned(
                meal: 2,
                p: 30,
                c: 40,
                f: 10,
                kcal: 370,
                status: .planned,
                scheduled: nextTimeString(addingMinutes: 60)
            ),
        ])
        viewModel.scheduleMealReminders(notifications: mock)
        let reminders = mock.scheduledNotifications.filter { $0.category == "meal_reminder" }
        XCTAssertEqual(reminders.count, 1, "Only the planned meal should be scheduled")
    }

    func testScheduleMealReminders_skipsPastTimes() throws {
        try skipNearMidnight()
        let mock = MockNotificationService()
        viewModel._testSetTodayMeals([
            // Scheduled 30 minutes ago — skipped because the 5-min-prior fire time is in the past.
            makePlanned(
                meal: 1,
                p: 30,
                c: 40,
                f: 10,
                kcal: 370,
                status: .planned,
                scheduled: nextTimeString(addingMinutes: -30)
            ),
        ])
        viewModel.scheduleMealReminders(notifications: mock)
        let reminders = mock.scheduledNotifications.filter { $0.category == "meal_reminder" }
        XCTAssertTrue(reminders.isEmpty)
    }

    // MARK: - Helpers

    private func makePlanned(
        meal: Int, p: Double, c: Double, f: Double, kcal: Double,
        status: MealStatus, scheduled: String = "12:00"
    ) -> PlannedMeal {
        PlannedMeal(
            dayDate: Date(),
            mealNumber: meal,
            mealName: "Meal \(meal)",
            scheduledTime: scheduled,
            foods: [],
            totalCalories: kcal,
            totalProtein: p,
            totalCarbs: c,
            totalFat: f,
            status: status
        )
    }

    // MARK: - Today's supplement decisions (weekday-key resolution)

    func testTodaySupplementDecisions_resolvesTodayByPlanDayIndex() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Anchor the plan to THIS week's Monday, matching persistPlan.
        let weekdayOfToday = cal.component(.weekday, from: today) // 1=Sun..7=Sat
        let mondayOffset = (weekdayOfToday + 5) % 7 // days since Monday
        let monday = try XCTUnwrap(cal.date(byAdding: .day, value: -mondayOffset, to: today))
        let sunday = try XCTUnwrap(cal.date(byAdding: .day, value: 6, to: monday))

        let plan = WeeklyMealPlan(
            startDate: monday, endDate: sunday,
            dayTypeAssignments: [:], isActive: true
        )
        // Key each day (1=Mon..7=Sun) to a uniquely named supplement so we can
        // prove the resolver picks TODAY's, not a neighbor's (off-by-one guard).
        var decisions: [Int: [SupplementDecision]] = [:]
        for key in 1 ... 7 {
            decisions[key] = [SupplementDecision(name: "Day\(key)", take: true, reason: nil)]
        }
        plan.supplementDecisions = decisions
        viewModel._testSetWeeklyPlan(plan)

        let todayKey = mondayOffset + 1 // (days since Monday) + 1
        let resolved = viewModel.todaySupplementDecisions
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(
            resolved.first?.name,
            "Day\(todayKey)",
            "Must resolve TODAY's decisions, not a neighboring day's"
        )
    }

    func testTodaySupplementDecisions_emptyWhenNoPlan() {
        viewModel._testSetWeeklyPlan(nil)
        XCTAssertTrue(viewModel.todaySupplementDecisions.isEmpty)
    }

    /// "HH:mm" + 60 min wraps past midnight after 23:00 and reads as a past
    /// time, so these reminder tests would fail on the clock, not the code.
    private func skipNearMidnight() throws {
        let hour = Calendar.current.component(.hour, from: Date())
        // ±60-minute HH:mm offsets wrap across midnight from 22:00 to 01:59.
        try XCTSkipIf(hour >= 22 || hour < 2, "HH:mm offsets wrap past midnight around midnight")
    }

    private func nextTimeString(addingMinutes minutes: Int) -> String {
        let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Undo meal eaten

    //
    // All three tests share the SINGLE setUp `container`. Standing up a SECOND
    // in-memory container mid-test (both registering PlannedMeal) traps
    // SwiftData on insert — that, not MealFeedback-in-schema, was the crash.

    func testUndoMealEaten_revertsStatusClearsTimeAndDeletesFeedback() throws {
        let ctx = container.mainContext
        let meal = makePlanned(meal: 1, p: 20, c: 80, f: 10, kcal: 480, status: .eaten)
        meal.actualEatenAt = Date()
        ctx.insert(meal)
        let feedback = MealFeedback(plannedMeal: meal, mealFeel: .clean)
        ctx.insert(feedback)
        try ctx.save()

        viewModel.undoMealEaten(meal, modelContext: ctx)

        XCTAssertEqual(meal.status, .planned, "Undo must revert to planned")
        XCTAssertNil(meal.actualEatenAt, "Eaten time must be cleared")
        let remaining = (try? ctx.fetch(FetchDescriptor<MealFeedback>())) ?? []
        XCTAssertTrue(remaining.isEmpty, "The meal's feedback row must be deleted")
    }

    func testUndoMealEaten_reCreditsPantryWhenDecrementedThenResetsFlag() throws {
        let ctx = container.mainContext
        let meal = makePlanned(meal: 1, p: 5, c: 40, f: 2, kcal: 200, status: .eaten)
        // Non-staple, grams unit so re-credit is direct: 1000 − 153 (eaten) =
        // 847; undo adds 153 back → 1000.
        meal.foods = [PlannedFood(
            name: "rice",
            quantityGrams: 153,
            calories: 200,
            proteinG: 5,
            carbsG: 40,
            fatG: 2
        )]
        meal.didDecrementPantry = true
        let rice = PantryItem(
            canonicalName: "rice",
            displayName: "Rice",
            quantity: 847,
            unit: .grams,
            storageLocation: .pantry
        )
        ctx.insert(meal)
        ctx.insert(rice)
        try ctx.save()

        viewModel.undoMealEaten(meal, modelContext: ctx)

        XCTAssertEqual(
            rice.quantity,
            1000,
            accuracy: 0.001,
            "Undo must re-credit the 153g it had decremented"
        )
        XCTAssertFalse(
            meal.didDecrementPantry,
            "Flag reset so a re-log can decrement again"
        )
    }

    func testUndoMealEaten_doesNotCreditPantryWhenNeverDecremented() throws {
        let ctx = container.mainContext
        // "Ate out" substitute: eaten but pantry never touched (flag false).
        let meal = makePlanned(meal: 1, p: 5, c: 40, f: 2, kcal: 200, status: .eaten)
        meal.foods = [PlannedFood(
            name: "rice",
            quantityGrams: 153,
            calories: 200,
            proteinG: 5,
            carbsG: 40,
            fatG: 2
        )]
        meal.didDecrementPantry = false
        let rice = PantryItem(
            canonicalName: "rice",
            displayName: "Rice",
            quantity: 500,
            unit: .grams,
            storageLocation: .pantry
        )
        ctx.insert(meal)
        ctx.insert(rice)
        try ctx.save()

        viewModel.undoMealEaten(meal, modelContext: ctx)

        XCTAssertEqual(
            rice.quantity,
            500,
            "No decrement happened → undo must not invent stock"
        )
    }

    // MARK: - Supplement "taken" toggle (idempotent)

    func testToggleSupplementTaken_insertsThenDeletes() {
        let ctx = container.mainContext
        XCTAssertFalse(viewModel.takenSupplementsToday(modelContext: ctx).contains("Creatine"))

        // First tap → taken.
        viewModel.toggleSupplementTaken(name: "Creatine", modelContext: ctx)
        XCTAssertTrue(viewModel.takenSupplementsToday(modelContext: ctx).contains("Creatine"))

        // Second tap → undone (idempotent, no orphan rows).
        viewModel.toggleSupplementTaken(name: "Creatine", modelContext: ctx)
        XCTAssertFalse(viewModel.takenSupplementsToday(modelContext: ctx).contains("Creatine"))

        let rows = (try? ctx.fetch(FetchDescriptor<SupplementIntakeLog>())) ?? []
        XCTAssertTrue(rows.isEmpty, "Toggle off must leave NO rows")
    }

    func testToggleSupplementTaken_twoSupplementsIndependent() {
        let ctx = container.mainContext
        viewModel.toggleSupplementTaken(name: "Creatine", modelContext: ctx)
        viewModel.toggleSupplementTaken(name: "Whey", modelContext: ctx)
        let taken = viewModel.takenSupplementsToday(modelContext: ctx)
        XCTAssertTrue(taken.contains("Creatine"))
        XCTAssertTrue(taken.contains("Whey"))

        viewModel.toggleSupplementTaken(name: "Creatine", modelContext: ctx)
        let after = viewModel.takenSupplementsToday(modelContext: ctx)
        XCTAssertFalse(after.contains("Creatine"))
        XCTAssertTrue(after.contains("Whey"), "Toggling one must not affect the other")
    }

    func testUndoMealEaten_revertsASkippedMealToPlanned() throws {
        // Un-skip: undoMealEaten is status-agnostic. A skipped meal never
        // decremented pantry or stored feedback, so undo just flips it back
        // to planned so it counts again.
        let ctx = container.mainContext
        let meal = makePlanned(meal: 1, p: 30, c: 60, f: 15, kcal: 500, status: .skipped)
        ctx.insert(meal)
        try ctx.save()

        viewModel.undoMealEaten(meal, modelContext: ctx)

        XCTAssertEqual(meal.status, .planned, "Undo skip must put the meal back to planned")
        XCTAssertNil(meal.actualEatenAt)
    }
}
