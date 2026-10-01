//
// MealOutcomeServiceTests.swift
// Tempo
//
// The single eat / skip / undo / delete path. Pins: undo of an ad-hoc log
// removes it (meal + MealLog + feedback), undo of a plan slot restores the
// planned dish, logging into a slot by name works for 3/4/5/6-meal plans,
// pantry credit is exact, presets go through the recorder.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class MealOutcomeServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var env: MealOutcomeService.Env!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        env = MealOutcomeService.Env(modelContext: context)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        env = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func food(_ name: String, kcal: Double) -> MealFoodItemInput {
        MealFoodItemInput(
            foodId: UUID().uuidString, name: name, brand: nil, servings: 1,
            servingSize: 100, servingUnit: "g", calories: kcal,
            proteinGrams: 10, carbsGrams: 20, fatGrams: 5, source: .manual
        )
    }

    private func plan() -> WeeklyMealPlan {
        let today = Calendar.current.startOfDay(for: Date())
        let p = WeeklyMealPlan(
            startDate: Calendar.current.date(byAdding: .day, value: -1, to: today)!,
            endDate: Calendar.current.date(byAdding: .day, value: 5, to: today)!
        )
        context.insert(p)
        return p
    }

    @discardableResult
    private func slot(
        _ name: String, number: Int, time: String = "12:00", kcal: Double = 700,
        dish: String = "Planned dish", in plan: WeeklyMealPlan
    ) -> PlannedMeal {
        let meal = PlannedMeal(
            dayDate: Date(), mealNumber: number, mealName: name, scheduledTime: time,
            foods: [PlannedFood(name: dish, quantityGrams: 300, calories: kcal, proteinG: 40, carbsG: 60, fatG: 20)],
            totalCalories: kcal, totalProtein: 40, totalCarbs: 60, totalFat: 20,
            status: .planned, mealPlan: plan
        )
        context.insert(meal)
        return meal
    }

    private func meals() -> [PlannedMeal] {
        (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
    }

    // MARK: - Ad-hoc removal

    func testUndoOfAdHocLogRemovesMealMealLogAndFeedback() throws {
        let result = try EatenMealRecorder.record(
            [food("Toast", kcal: 200)], type: .breakfast, eatenAt: Date(), source: .manual, modelContext: context
        )
        let meal = result.meal
        XCTAssertTrue(meal.isUnplannedLog)
        context.insert(MealFeedback(plannedMeal: meal, mealFeel: .light, satiety: .justRight))
        try context.save()

        let snap = try MealOutcomeService.undo(meal, env: env)

        XCTAssertEqual(snap.kind, .removed)
        XCTAssertTrue(meals().isEmpty)
        XCTAssertEqual((try context.fetch(FetchDescriptor<MealLog>())).count, 0)
        XCTAssertEqual((try context.fetch(FetchDescriptor<MealFeedback>())).count, 0)
    }

    func testRestoreAfterRemovalBringsAdHocLogBack() throws {
        let result = try EatenMealRecorder.record(
            [food("Toast", kcal: 200)], type: .breakfast, eatenAt: Date(), source: .manual, modelContext: context
        )
        let snap = try MealOutcomeService.undo(result.meal, env: env)
        try MealOutcomeService.restore(snap, env: env)
        let back = CanonicalMeals.eatenMeals(on: Date(), in: context)
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back.first?.totalCalories, 200)
    }

    // MARK: - Plan slot replace + undo

    func testLoggingIntoSlotReplacesDishAndUndoRestoresIt() throws {
        let p = plan()
        let lunch = slot("Lunch", number: 2, in: p)
        try EatenMealRecorder.record(
            [food("Burrito", kcal: 900)], type: .lunch, eatenAt: Date(), source: .manual, modelContext: context
        )
        XCTAssertEqual(lunch.status, .eaten)
        XCTAssertEqual(lunch.foods.map(\.name), ["Burrito"])
        XCTAssertFalse(lunch.isUnplannedLog)

        let snap = try MealOutcomeService.undo(lunch, env: env)

        XCTAssertEqual(snap.kind, .revertedToPlanned)
        XCTAssertEqual(lunch.status, .planned)
        XCTAssertEqual(lunch.foods.map(\.name), ["Planned dish"])
        XCTAssertEqual(lunch.totalCalories, 700)
        XCTAssertNil(lunch.actualEatenAt)
        XCTAssertNil(lunch.linkedMealLogID)
        XCTAssertEqual(meals().count, 1)
        XCTAssertEqual((try context.fetch(FetchDescriptor<MealLog>())).count, 0)
    }

    func testDeleteThenRestoreReappliesLog() throws {
        let p = plan()
        let lunch = slot("Lunch", number: 2, in: p)
        try EatenMealRecorder.record(
            [food("Burrito", kcal: 900)], type: .lunch, eatenAt: Date(), source: .manual, modelContext: context
        )
        let snap = try MealOutcomeService.deleteLog(lunch, env: env)
        try MealOutcomeService.restore(snap, env: env)
        XCTAssertEqual(lunch.status, .eaten)
        XCTAssertEqual(lunch.foods.map(\.name), ["Burrito"])
    }

    func testMarkEatenDoesNotTouchUnplannedFlagOfPlanMealWithNilBaseline() throws {
        let meal = PlannedMeal(
            dayDate: Date(), mealNumber: 1, mealName: "Breakfast", scheduledTime: "08:00",
            foods: [], totalCalories: 400, totalProtein: 20, totalCarbs: 40, totalFat: 10, status: .planned
        )
        context.insert(meal)
        try MealOutcomeService.markEaten(meal, pantry: .none, env: env)
        XCTAssertEqual(meal.status, .eaten)
        XCTAssertFalse(meal.isUnplannedLog)
        let snap = try MealOutcomeService.undo(meal, env: env)
        XCTAssertEqual(snap.kind, .revertedToPlanned)
        XCTAssertEqual(meal.status, .planned)
    }

    func testMarkEatenTwiceOnlyUpdatesTime() throws {
        let p = plan()
        let m = slot("Dinner", number: 3, time: "19:00", in: p)
        try MealOutcomeService.markEaten(m, pantry: .none, env: env)
        let later = Date().addingTimeInterval(-60)
        try MealOutcomeService.markEaten(m, at: later, pantry: .none, env: env)
        XCTAssertEqual(m.actualEatenAt, later)
        XCTAssertEqual(m.status, .eaten)
    }

    func testMarkEatenPostsNutritionLogged() throws {
        let p = plan()
        let m = slot("Dinner", number: 3, time: "19:00", in: p)
        let posted = expectation(forNotification: .tempoNutritionLogged, object: nil)
        try MealOutcomeService.markEaten(m, pantry: .none, env: env)
        wait(for: [posted], timeout: 1)
    }

    // MARK: - Skip

    func testSkipAndUnskip() throws {
        let p = plan()
        let m = slot("Snack", number: 4, time: "16:00", in: p)
        try MealOutcomeService.skip(m, env: env)
        XCTAssertEqual(m.status, .skipped)
        let snap = try MealOutcomeService.undo(m, env: env)
        XCTAssertEqual(snap.kind, .revertedToPlanned)
        XCTAssertEqual(m.status, .planned)
    }

    func testSkipIgnoresEatenMeal() throws {
        let p = plan()
        let m = slot("Snack", number: 4, time: "16:00", in: p)
        try MealOutcomeService.markEaten(m, pantry: .none, env: env)
        try MealOutcomeService.skip(m, env: env)
        XCTAssertEqual(m.status, .eaten)
    }

    // MARK: - Slot matching for 3/4/5/6 meal plans

    func testSlotMatchingByNameForFiveMealPlan() throws {
        let p = plan()
        let b = slot("Breakfast", number: 1, time: "07:30", in: p)
        let s1 = slot("Mid-Morning Snack", number: 2, time: "10:30", in: p)
        let l = slot("Lunch", number: 3, time: "13:00", in: p)
        let s2 = slot("Afternoon Snack", number: 4, time: "16:30", in: p)
        let d = slot("Dinner", number: 5, time: "20:00", in: p)

        let dinner = try EatenMealRecorder.record(
            [food("Steak", kcal: 800)], type: .dinner, eatenAt: Date(), source: .manual, modelContext: context
        )
        XCTAssertTrue(dinner.meal === d, "Dinner is not mealNumber 4 / sortOrder+1")
        XCTAssertEqual([b, s1, l, s2].filter { $0.status == .eaten }.count, 0)

        let lunch = try EatenMealRecorder.record(
            [food("Pasta", kcal: 600)], type: .lunch, eatenAt: Date(), source: .manual, modelContext: context
        )
        XCTAssertTrue(lunch.meal === l)
    }

    func testSnackNeverLandsInDinnerSlotAndSixMealPlan() throws {
        let p = plan()
        slot("Breakfast", number: 1, time: "07:00", in: p)
        slot("Snack 1", number: 2, time: "10:00", in: p)
        slot("Lunch", number: 3, time: "13:00", in: p)
        let s2 = slot("Snack 2", number: 4, time: "16:00", in: p)
        let d = slot("Dinner", number: 5, time: "19:30", in: p)
        slot("Evening Snack", number: 6, time: "22:00", in: p)

        let snack = try EatenMealRecorder.record(
            [food("Bar", kcal: 200)], type: .snack,
            eatenAt: Calendar.current.date(bySettingHour: 16, minute: 5, second: 0, of: Date())!,
            source: .manual, modelContext: context
        )
        XCTAssertTrue(snack.meal === s2, "Closest snack by time")
        XCTAssertNotEqual(d.status, .eaten)
    }

    func testThreeMealPlanSnackBecomesAdHoc() throws {
        let p = plan()
        slot("Breakfast", number: 1, in: p)
        slot("Lunch", number: 2, in: p)
        let d = slot("Dinner", number: 3, in: p)
        let r = try EatenMealRecorder.record(
            [food("Bar", kcal: 200)], type: .snack, eatenAt: Date(), source: .manual, modelContext: context
        )
        XCTAssertFalse(r.meal === d)
        XCTAssertTrue(r.meal.isUnplannedLog)
        XCTAssertEqual(d.status, .planned)
    }

    func testMealTypeInferredFromName() {
        XCTAssertEqual(MealType.inferred(fromName: "Breakfast"), .breakfast)
        XCTAssertEqual(MealType.inferred(fromName: "Brunch"), .breakfast)
        XCTAssertEqual(MealType.inferred(fromName: "Lunch"), .lunch)
        XCTAssertEqual(MealType.inferred(fromName: "Dinner"), .dinner)
        XCTAssertEqual(MealType.inferred(fromName: "Dinner snack"), .snack)
        XCTAssertEqual(MealType.inferred(fromName: "Afternoon Snack"), .snack)
        XCTAssertNil(MealType.inferred(fromName: "Meal 3"))
    }

    // MARK: - Pantry exactness

    func testUndoCreditsPantryExactly() throws {
        let item = PantryItem(rawName: "Chicken", quantity: 1000, unit: .grams)
        context.insert(item)
        let p = plan()
        let m = slot("Lunch", number: 2, dish: "Chicken", in: p)
        try context.save()
        try MealOutcomeService.markEaten(m, env: env)
        let after = item.quantity
        XCTAssertLessThanOrEqual(after, 1000)
        _ = try MealOutcomeService.undo(m, env: env)
        XCTAssertEqual(item.quantity, 1000, accuracy: 0.001)
        XCTAssertFalse(m.didDecrementPantry)
    }

    // MARK: - Presets

    func testSavePresetFromLoggedFoods() throws {
        let foods = [PlannedFood(name: "Oats", quantityGrams: 80, calories: 300, proteinG: 10, carbsG: 50, fatG: 6)]
        let preset = try MealOutcomeService.savePreset(
            name: "Usual", foods: foods, mealType: .breakfast, modelContext: context
        )
        XCTAssertEqual(preset.totalCalories, 300)
        XCTAssertEqual(preset.foodItems.map(\.name), ["Oats"])
        XCTAssertEqual((try context.fetch(FetchDescriptor<MealPreset>())).count, 1)
    }

    func testPresetLogGoesThroughRecorderAndHitsCanonicalReaders() throws {
        let vm = NutritionTabViewModel()
        let preset = MealPreset(
            name: "Usual", foodItems: [food("Oats", kcal: 300)], totalCalories: 300,
            totalProtein: 10, totalCarbs: 20, totalFat: 5, mealType: .breakfast
        )
        context.insert(preset)
        let r = vm.logFromPreset(preset, modelContext: context)
        XCTAssertNotNil(r)
        XCTAssertEqual(CanonicalMeals.eatenMeals(on: Date(), in: context).count, 1)
    }

    // MARK: - Serving-size grams (the "2 eggs" bug)

    func testGramsFromServingSize() {
        let g = EatenMealRecorder.gramsFromServingSize
        XCTAssertEqual(g("2 eggs"), 0)
        XCTAssertEqual(g("1 serving"), 0)
        XCTAssertEqual(g("1 large bowl"), 0)
        XCTAssertEqual(g("100 g"), 100)
        XCTAssertEqual(g("1 cup (240 ml)"), 240)
        XCTAssertEqual(g("2 oz"), 56.699, accuracy: 0.01)
        XCTAssertEqual(g("1.5 kg"), 1500)
        XCTAssertEqual(g("1,5 l"), 1500)
        XCTAssertEqual(g("1 slice (30g)"), 30)
    }

    // MARK: - Replaced plan model

    func testIsUnplannedLogOnlyWhenBaselineExplicitlyZero() {
        let m = PlannedMeal(
            dayDate: Date(), mealNumber: 1, mealName: "X", scheduledTime: "08:00",
            foods: [], totalCalories: 1, totalProtein: 1, totalCarbs: 1, totalFat: 1, status: .planned
        )
        XCTAssertFalse(m.isUnplannedLog)
        m.markAsUnplannedLog()
        XCTAssertTrue(m.isUnplannedLog)
    }

    // MARK: - Undo of a skip restores a skip

    func testRestoreAfterUndoingASkipSkipsAgainInsteadOfEating() throws {
        let p = plan()
        let m = slot("Snack", number: 4, time: "16:00", in: p)
        try MealOutcomeService.skip(m, env: env)
        let snap = try MealOutcomeService.undo(m, env: env)
        XCTAssertEqual(snap.priorStatus, .skipped)
        XCTAssertEqual(m.status, .planned)

        try MealOutcomeService.restore(snap, env: env)

        XCTAssertEqual(m.status, .skipped)
        XCTAssertFalse(m.didDecrementPantry, "Restoring a skip never touches the pantry")
    }

    func testRestoreAfterUndoOnAMovedMealNeverMarksItEaten() throws {
        let p = plan()
        let m = slot("Lunch", number: 2, time: "13:00", in: p)
        m.status = .modified
        try context.save()
        let snap = try MealOutcomeService.undo(m, env: env)

        try MealOutcomeService.restore(snap, env: env)

        XCTAssertEqual(m.status, .modified)
        XCTAssertNil(m.actualEatenAt)
        XCTAssertTrue(CanonicalMeals.eatenMeals(on: Date(), in: context).isEmpty)
    }

    func testRestoringASkipSpreadsItsMacrosAgain() throws {
        let p = plan()
        let lunch = slot("Lunch", number: 2, time: "23:00", kcal: 700, in: p)
        let snack = slot("Snack", number: 3, time: "23:30", kcal: 300, in: p)
        try context.save()
        try MealOutcomeService.skip(snack, env: env)
        let snap = try MealOutcomeService.undo(snack, env: env)
        XCTAssertEqual(lunch.totalCalories, 700, accuracy: 1)

        try MealOutcomeService.restore(snap, env: env)

        XCTAssertEqual(snack.status, .skipped)
        XCTAssertGreaterThan(lunch.totalCalories, 700, "The skipped snack's calories move to lunch again")
    }

    func testRestoredLogKeepsItsFeedbackAndItsDay() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let result = try EatenMealRecorder.record(
            [food("Toast", kcal: 200)], type: .breakfast, eatenAt: yesterday, source: .manual,
            modelContext: context, now: yesterday
        )
        context.insert(MealFeedback(plannedMeal: result.meal, mealFeel: .light, satiety: .justRight))
        try context.save()
        let snap = try MealOutcomeService.undo(result.meal, env: env)

        try MealOutcomeService.restore(snap, env: env)

        let back = try XCTUnwrap(meals().first)
        XCTAssertTrue(Calendar.current.isDate(back.dayDate, inSameDayAs: yesterday))
        let feedback = try context.fetch(FetchDescriptor<MealFeedback>())
        XCTAssertEqual(feedback.count, 1)
        XCTAssertEqual(feedback.first?.mealFeel, .light)
    }

    // MARK: - Legacy / flag semantics

    func testExplicitFalseFlagNeverReadsAsALogEvenWithZeroBaseline() {
        let m = PlannedMeal(
            dayDate: Date(), mealNumber: 1, mealName: "X", scheduledTime: "08:00",
            foods: [], totalCalories: 1, totalProtein: 1, totalCarbs: 1, totalFat: 1, status: .eaten
        )
        m.planBaselineCalories = 0
        m.planBaselineProtein = 0
        m.planBaselineCarbs = 0
        m.planBaselineFat = 0
        XCTAssertTrue(m.isUnplannedLog, "Legacy zero baseline (flag nil) still reads as a log")
        m.isUnplannedLogFlag = false
        XCTAssertFalse(m.isUnplannedLog)
    }

    // MARK: - Shared environment

    func testSkipCancelsRemindersThroughTheSuppliedNotificationService() throws {
        let p = plan()
        let m = slot("Dinner", number: 3, time: "19:00", in: p)
        let notifications = MockNotificationService()
        notifications.scheduleOverdueMealReminder(
            mealID: m.id, mealName: "Dinner", scheduledTime: Date().addingTimeInterval(3600), lateMinutes: 30
        )
        XCTAssertEqual(notifications.scheduledNotifications.count, 1)

        // The Coach tool path.
        _ = try CoachTools.skipMeal(
            mealID: m.id,
            outcomeEnv: { MealOutcomeService.Env.live(modelContext: $0, notifications: notifications, whoop: nil) },
            context: context
        )

        XCTAssertEqual(m.status, .skipped)
        XCTAssertTrue(notifications.scheduledNotifications.isEmpty)
    }

    func testUndoPutsShiftedMealsBackOnTheirPlanTimes() throws {
        let p = plan()
        let breakfast = slot("Breakfast", number: 1, time: "08:00", in: p)
        let lunch = slot("Lunch", number: 2, time: "13:00", in: p)
        let dinner = slot("Dinner", number: 3, time: "19:30", in: p)
        let lateBreakfast = Calendar.current.date(bySettingHour: 11, minute: 30, second: 0, of: Date())!

        try MealOutcomeService.markEaten(breakfast, at: lateBreakfast, env: env)
        XCTAssertNotEqual(lunch.scheduledTime, "13:00", "Eating 3.5 h late pushes lunch back")

        _ = try MealOutcomeService.undo(breakfast, env: env)
        XCTAssertEqual(lunch.scheduledTime, "13:00")
        XCTAssertEqual(dinner.scheduledTime, "19:30")
        XCTAssertEqual(breakfast.scheduledTime, "08:00")
        XCTAssertNil(lunch.originalScheduledTime)
    }

    func testOverdueNotificationButtonsUseTheSharedPath() throws {
        let p = plan()
        let lunch = slot("Lunch", number: 2, time: "12:00", in: p)
        let dinner = slot("Dinner", number: 3, time: "19:00", in: p)
        let notifications = MockNotificationService()
        let live = MealOutcomeService.Env.live(modelContext: context, notifications: notifications, whoop: nil)

        XCTAssertTrue(TempoNotificationDelegate.resolveOverdueMeal(id: lunch.id.uuidString, ate: true, env: live))
        XCTAssertEqual(lunch.status, .eaten)
        XCTAssertNotNil(lunch.actualEatenAt)
        XCTAssertTrue(TempoNotificationDelegate.resolveOverdueMeal(id: dinner.id.uuidString, ate: false, env: live))
        XCTAssertEqual(dinner.status, .skipped)

        // Already answered in the app → the late button press changes nothing.
        XCTAssertFalse(TempoNotificationDelegate.resolveOverdueMeal(id: lunch.id.uuidString, ate: false, env: live))
        XCTAssertEqual(lunch.status, .eaten)
        XCTAssertFalse(TempoNotificationDelegate.resolveOverdueMeal(id: "not-a-uuid", ate: true, env: live))
    }

    func testRebalanceUsesWhoopTDEEAndStoredRecoveryLikeTheTodayRing() throws {
        let whoop = MockWhoopService()
        let live = MealOutcomeService.Env.live(modelContext: context, notifications: nil, whoop: whoop)
        XCTAssertEqual(live.whoopAvgTDEE, whoop.weeklyTDEEAverage)
        XCTAssertNil(live.recoveryScore, "Falls back to the stored score at rebalance time")
        XCTAssertNil(DailyNutritionTargets.storedRecoveryScore(in: context))
    }

    // MARK: - Review fixes (PR #69)

    func testCoachMovedModifiedMealIsStillRebalancedAndShifted() throws {
        let p = plan()
        let breakfast = slot("Breakfast", number: 1, time: "08:00", kcal: 600, in: p)
        let lunch = slot("Lunch", number: 2, time: "13:00", kcal: 700, in: p)
        lunch.status = .modified
        let lateBreakfast = Calendar.current.date(bySettingHour: 11, minute: 30, second: 0, of: Date())!

        try MealOutcomeService.markEaten(
            breakfast, at: lateBreakfast, replacingWith: [
                PlannedFood(name: "Feast", quantityGrams: 900, calories: 3000, proteinG: 100, carbsG: 300, fatG: 100),
            ], pantry: .none, env: env
        )

        XCTAssertNotEqual(lunch.scheduledTime, "13:00", "A .modified meal still shifts")
        XCTAssertLessThan(lunch.totalCalories, 700, "A .modified meal still absorbs the overshoot")
        XCTAssertEqual(lunch.status, .modified)
    }

    func testUndoWithNothingMatchedNeverCreditsPantryApproximately() throws {
        let item = PantryItem(rawName: "Chicken", quantity: 0, unit: .grams)
        context.insert(item)
        let p = plan()
        let m = slot("Lunch", number: 2, dish: "Chicken", in: p)
        try context.save()
        try MealOutcomeService.markEaten(m, env: env)
        for _ in 0..<2 {
            _ = try MealOutcomeService.undo(m, env: env)
            try MealOutcomeService.markEaten(m, env: env)
        }
        _ = try MealOutcomeService.undo(m, env: env)
        XCTAssertEqual(item.quantity, 0, accuracy: 0.001)
    }

    func testChangingWhatIAteSwapsPantryUseAndKeepsOneFeedbackRow() throws {
        let chicken = PantryItem(rawName: "Chicken", quantity: 1000, unit: .grams)
        let rice = PantryItem(rawName: "Rice", quantity: 1000, unit: .grams)
        context.insert(chicken)
        context.insert(rice)
        let p = plan()
        let m = slot("Lunch", number: 2, dish: "Chicken", in: p)
        try context.save()
        try MealOutcomeService.markEaten(m, feel: .light, env: env)
        XCTAssertLessThan(chicken.quantity, 1000)

        try MealOutcomeService.markEaten(
            m, satiety: .justRight,
            replacingWith: [PlannedFood(name: "Rice", quantityGrams: 200, calories: 260, proteinG: 5, carbsG: 56, fatG: 1)],
            substituteNote: "rice", pantry: .foods, env: env
        )

        XCTAssertEqual(chicken.quantity, 1000, accuracy: 0.001, "Old foods are credited back")
        XCTAssertEqual(rice.quantity, 800, accuracy: 0.001, "New foods are decremented")
        let rows = try context.fetch(FetchDescriptor<MealFeedback>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.mealFeel, .light)
        XCTAssertEqual(rows.first?.satiety, .justRight)

        _ = try MealOutcomeService.undo(m, env: env)
        XCTAssertEqual(rice.quantity, 1000, accuracy: 0.001)
        XCTAssertEqual(chicken.quantity, 1000, accuracy: 0.001)
    }

    func testDeletingAnAdHocLogGrowsTheTrimmedMealsBack() throws {
        let p = plan()
        let lunch = slot("Lunch", number: 2, time: "23:00", kcal: 700, in: p)
        let log = try EatenMealRecorder.record(
            [food("Feast", kcal: 2500)], type: .snack, eatenAt: Date(), source: .manual, modelContext: context
        ).meal
        MealOutcomeService.applyMacroRebalance(env: env)
        let trimmed = lunch.totalCalories
        XCTAssertLessThan(trimmed, 700)

        _ = try MealOutcomeService.deleteLog(log, env: env)

        XCTAssertGreaterThan(lunch.totalCalories, trimmed)
    }

    func testUndoOfALogThatFilledASkippedSlotReturnsItToSkipped() throws {
        let p = plan()
        let lunch = slot("Lunch", number: 2, in: p)
        try MealOutcomeService.skip(lunch, env: env)
        try MealOutcomeService.markEaten(
            lunch, replacingWith: [PlannedFood(name: "Burrito", quantityGrams: 300, calories: 800, proteinG: 30, carbsG: 90, fatG: 30)],
            pantry: .none, env: env
        )
        XCTAssertEqual(lunch.status, .eaten)
        _ = try MealOutcomeService.undo(lunch, env: env)
        XCTAssertEqual(lunch.status, .skipped)
    }

    func testRestoreOfAMealThatIsGoneThrows() throws {
        let p = plan()
        let lunch = slot("Lunch", number: 2, in: p)
        try MealOutcomeService.markEaten(lunch, pantry: .none, env: env)
        let snap = try MealOutcomeService.undo(lunch, env: env)
        context.delete(lunch)
        try context.save()
        XCTAssertThrowsError(try MealOutcomeService.restore(snap, env: env))
    }

    func testSkipUndoAndDeleteRequestAReplan() throws {
        let p = plan()
        let lunch = slot("Lunch", number: 2, in: p)
        var count = 0
        let token = NotificationCenter.default.addObserver(
            forName: .tempoDayPlanReplanRequested, object: nil, queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        try MealOutcomeService.skip(lunch, env: env)
        XCTAssertEqual(count, 1)
        _ = try MealOutcomeService.undo(lunch, env: env)
        XCTAssertEqual(count, 2)
        let log = try EatenMealRecorder.record(
            [food("Toast", kcal: 200)], type: .snack, eatenAt: Date(), source: .manual, modelContext: context
        ).meal
        let before = count
        _ = try MealOutcomeService.deleteLog(log, env: env)
        XCTAssertGreaterThan(count, before)
    }

    func testEatingCancelsThePreMealFuelUpReminder() throws {
        let p = plan()
        let lunch = slot("Lunch", number: 2, in: p)
        let notifications = MockNotificationService()
        notifications.scheduleMealReminder(mealName: "Lunch", time: Date().addingTimeInterval(3600))
        let live = MealOutcomeService.Env(modelContext: context, notifications: notifications)
        XCTAssertEqual(notifications.scheduledNotifications.count, 1)
        try MealOutcomeService.markEaten(lunch, pantry: .none, env: live)
        XCTAssertTrue(notifications.scheduledNotifications.isEmpty)
    }
}
