//
// PlanRebuildFromTodayTests.swift
// Tempo
//
// Regenerating a plan must never destroy what already happened this week:
// past days stay as they were, today keeps its eaten / skipped meals, only
// still-planned meals from today on are replaced, nothing is duplicated, and
// the new remaining meals fit what today still needs.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class PlanRebuildFromTodayTests: XCTestCase {
    private let calendar = Calendar.current
    private var container: ModelContainer!
    private var context: ModelContext!
    private var profile: DietaryProfile!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: Schema(TempoSchemaV1.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = container.mainContext
        profile = DietaryProfile(currentWeightKg: 78)
        context.insert(profile)
    }

    override func tearDown() async throws {
        context = nil
        profile = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    /// Wed 30 Sep 2026, midday. The week's Monday is 28 Sep.
    private var now: Date { day(2026, 9, 30, hour: 12) }
    private var monday: Date { day(2026, 9, 28) }

    @discardableResult
    private func addMeal(
        _ plan: WeeklyMealPlan,
        dayOffset: Int,
        number: Int,
        name: String,
        kcal: Double,
        status: MealStatus = .planned,
        baseline: Double? = nil
    ) -> PlannedMeal {
        let meal = PlannedMeal(
            dayDate: calendar.date(byAdding: .day, value: dayOffset, to: monday)!,
            mealNumber: number,
            mealName: name,
            scheduledTime: "12:00",
            foods: [PlannedFood(name: "old food", quantityGrams: 100, calories: kcal, proteinG: 10, carbsG: 10, fatG: 5)],
            totalCalories: kcal,
            totalProtein: 10,
            totalCarbs: 10,
            totalFat: 5,
            status: status,
            actualEatenAt: status == .eaten ? now : nil,
            mealPlan: plan
        )
        if let baseline {
            meal.planBaselineCalories = baseline
            meal.planBaselineProtein = 10
            meal.planBaselineCarbs = 10
            meal.planBaselineFat = 5
        }
        context.insert(meal)
        return meal
    }

    private func seedWeek() -> WeeklyMealPlan {
        let plan = WeeklyMealPlan(
            startDate: monday,
            endDate: calendar.date(byAdding: .day, value: 6, to: monday)!,
            dayTypeAssignments: [1: "strength", 2: "rest", 3: "cardio", 4: "strength"]
        )
        plan.supplementDecisionsJSON = try? JSONEncoder().encode([
            1: [SupplementDecision(name: "OldCreatine", take: true, timing: nil, reason: nil)],
            3: [SupplementDecision(name: "OldD3", take: true, timing: nil, reason: nil)],
        ])
        context.insert(plan)
        return plan
    }

    /// 7 days x 3 meals (600 / 800 / 800 kcal), day types all "double".
    private func weekJSON(suppName: String = "NewCreatine") -> String {
        func meal(_ n: Int, _ name: String, _ kcal: Int) -> String {
            """
            {"mealNumber":\(n),"mealName":"\(name)","scheduledTime":"12:00","foods":[
              {"name":"new \(name)","quantityGrams":300,"calories":\(kcal),"proteinG":\(kcal / 10),"carbsG":\(kcal / 8),"fatG":\(kcal / 30),"source":"usda"}]}
            """
        }
        let days = (0 ..< 7).map { i in
            """
            {"dayIndex":\(i),"dayType":"double","meals":[\(meal(1, "Breakfast", 600)),\(meal(2, "Lunch", 800)),\(meal(3, "Dinner", 800))],
             "supplements":[{"name":"\(suppName)","take":true,"timing":null,"reason":null}]}
            """
        }
        return "{\"days\":[\(days.joined(separator: ","))]}"
    }

    private func rebuild(weekStart: Date? = nil, now overrideNow: Date? = nil) async throws -> WeeklyMealPlan {
        let prepared = MealPlanGeneratorService.PreparedWeeklyPlan(system: "", prompt: "", targets: [:], intake: nil)
        return try await MealPlanGeneratorService(apiClient: APIClient()).finishWeeklyPlan(
            weekJSON(),
            prepared: prepared,
            profile: profile,
            weekStart: weekStart ?? monday,
            macrosVerified: true,
            modelContext: context,
            attachingRecipes: false,
            now: overrideNow ?? now
        )
    }

    private func meals(of plan: WeeklyMealPlan, offset: Int) -> [PlannedMeal] {
        let date = calendar.date(byAdding: .day, value: offset, to: monday)!
        return (plan.meals ?? [])
            .filter { calendar.isDate($0.dayDate, inSameDayAs: date) }
            .sorted { $0.mealNumber < $1.mealNumber }
    }

    private func allPlans() -> [WeeklyMealPlan] {
        (try? context.fetch(FetchDescriptor<WeeklyMealPlan>())) ?? []
    }

    // MARK: - Tests

    func testRebuildKeepsActivePlanAndPastDaysUntouched() async throws {
        let plan = seedWeek()
        let mon = addMeal(plan, dayOffset: 0, number: 1, name: "Breakfast", kcal: 500, status: .eaten, baseline: 500)
        let tue = addMeal(plan, dayOffset: 1, number: 2, name: "Lunch", kcal: 700, status: .skipped, baseline: 700)
        let tuePlanned = addMeal(plan, dayOffset: 1, number: 3, name: "Dinner", kcal: 700)
        try context.save()
        let monID = mon.id, tueID = tue.id, tuePlannedID = tuePlanned.id

        let rebuilt = try await rebuild()

        XCTAssertEqual(rebuilt.id, plan.id, "The week's plan is updated in place, not replaced")
        XCTAssertEqual(allPlans().count, 1)
        XCTAssertTrue(rebuilt.isActive)
        XCTAssertFalse(rebuilt.isArchived)
        // Past days: exactly as they were — no new meals, status kept, a
        // past planned meal is history, not something to regenerate.
        XCTAssertEqual(meals(of: rebuilt, offset: 0).map(\.id), [monID])
        XCTAssertEqual(meals(of: rebuilt, offset: 0).first?.status, .eaten)
        XCTAssertEqual(Set(meals(of: rebuilt, offset: 1).map(\.id)), [tueID, tuePlannedID])
        XCTAssertEqual(meals(of: rebuilt, offset: 1).first { $0.id == tueID }?.status, .skipped)
        // Past day types + supplement decisions survive; today onward refresh.
        XCTAssertEqual(rebuilt.dayTypeAssignments[1], "strength")
        XCTAssertEqual(rebuilt.dayTypeAssignments[2], "rest")
        XCTAssertEqual(rebuilt.dayTypeAssignments[3], "double")
        XCTAssertEqual(rebuilt.supplementDecisions[1]?.first?.name, "OldCreatine")
        XCTAssertEqual(rebuilt.supplementDecisions[3]?.first?.name, "NewCreatine")
        // From today on: a full set of fresh meals every day.
        for offset in 2 ... 6 {
            XCTAssertEqual(meals(of: rebuilt, offset: offset).count, 3, "day offset \(offset)")
        }
    }

    func testTodayKeepsEatenAndSkippedAndNeverDuplicatesASlot() async throws {
        let plan = seedWeek()
        let breakfast = addMeal(plan, dayOffset: 2, number: 1, name: "Breakfast", kcal: 500, status: .eaten, baseline: 500)
        let oldLunch = addMeal(plan, dayOffset: 2, number: 2, name: "Lunch", kcal: 700)
        addMeal(plan, dayOffset: 2, number: 3, name: "Dinner", kcal: 700)
        try context.save()
        let breakfastID = breakfast.id, oldLunchID = oldLunch.id

        let rebuilt = try await rebuild()

        let today = meals(of: rebuilt, offset: 2)
        XCTAssertEqual(today.map(\.mealName), ["Breakfast", "Lunch", "Dinner"], "No duplicated Breakfast slot")
        XCTAssertEqual(today.first?.id, breakfastID)
        XCTAssertEqual(today.first?.status, .eaten)
        XCTAssertFalse(today.contains { $0.id == oldLunchID }, "The still-planned lunch is replaced")
        XCTAssertEqual(today.filter { $0.status == .planned }.count, 2)
    }

    func testTodayRemainingMealsFitWhatTheDayStillNeeds() async throws {
        let plan = seedWeek()
        // The plan's day is 600 + 800 + 800 = 2200. Breakfast was eaten as a
        // bigger substitute: baseline 600 (the slot), actually 900.
        let breakfast = addMeal(plan, dayOffset: 2, number: 1, name: "Breakfast", kcal: 900, status: .eaten, baseline: 600)
        _ = breakfast
        addMeal(plan, dayOffset: 2, number: 2, name: "Lunch", kcal: 800)
        try context.save()

        let rebuilt = try await rebuild()

        let today = meals(of: rebuilt, offset: 2)
        let remaining = today.filter { $0.status == .planned }
        XCTAssertEqual(remaining.count, 2)
        // Target stays the day's 2200 (sum of baselines) …
        let baselineSum = today.reduce(0.0) { $0 + $1.planBaseline.calories }
        XCTAssertEqual(baselineSum, 2200, accuracy: 2)
        // … and the new meals cover 2200 − 900 eaten = 1300, not 1600.
        let remainingKcal = remaining.reduce(0.0) { $0 + $1.totalCalories }
        XCTAssertEqual(remainingKcal, 1300, accuracy: 5)
        // The foods were scaled with the meal so the list still adds up.
        for meal in remaining {
            XCTAssertEqual(meal.foods.reduce(0.0) { $0 + $1.calories }, meal.totalCalories, accuracy: 3)
        }
    }

    func testSkippedMealIsKeptAndNotRegenerated() async throws {
        let plan = seedWeek()
        addMeal(plan, dayOffset: 2, number: 1, name: "Breakfast", kcal: 600, status: .skipped, baseline: 600)
        try context.save()

        let rebuilt = try await rebuild()

        let today = meals(of: rebuilt, offset: 2)
        XCTAssertEqual(today.filter { $0.mealName == "Breakfast" }.count, 1)
        XCTAssertEqual(today.first { $0.mealName == "Breakfast" }?.status, .skipped)
    }

    private func keptMeal(_ name: String, number: Int, time: String, in plan: WeeklyMealPlan) -> PlannedMeal {
        let meal = PlannedMeal(
            dayDate: monday, mealNumber: number, mealName: name, scheduledTime: time,
            totalCalories: 400, totalProtein: 20, totalCarbs: 40, totalFat: 10, status: .eaten, mealPlan: plan
        )
        meal.planBaselineCalories = 400
        meal.planBaselineProtein = 20
        meal.planBaselineCarbs = 40
        meal.planBaselineFat = 10
        return meal
    }

    private func slot(_ number: Int, _ name: String, _ time: String) -> PlanRebuild.Slot {
        PlanRebuild.Slot(mealNumber: number, mealName: name, scheduledTime: time)
    }

    func testAdHocLogDoesNotBlockAPlanSlot() {
        let plan = WeeklyMealPlan(startDate: monday, endDate: monday)
        let adHoc = PlannedMeal(dayDate: monday, mealNumber: 1, mealName: "Snack", totalCalories: 200, status: .eaten, mealPlan: plan)
        adHoc.markAsUnplannedLog()
        XCTAssertTrue(PlanRebuild.occupiedSlots(kept: [adHoc], slots: [slot(1, "Snack", "10:00")]).isEmpty)
    }

    func testOccupancyIsOneToOneForSameNamedSlots() {
        let plan = WeeklyMealPlan(startDate: monday, endDate: monday)
        let kept = [
            keptMeal("Snack", number: 2, time: "10:00", in: plan),
            keptMeal("Snack", number: 4, time: "15:00", in: plan),
        ]
        let slots = [slot(1, "Breakfast", "08:00"), slot(2, "Snack", "10:30"), slot(3, "Snack", "15:30"), slot(4, "Snack", "21:00")]
        // Two kept snacks take the two CLOSEST snack slots — the evening one stays.
        XCTAssertEqual(PlanRebuild.occupiedSlots(kept: kept, slots: slots), [1, 2])
    }

    func testOneKeptMealClaimsAtMostOneNewSlot() {
        let plan = WeeklyMealPlan(startDate: monday, endDate: monday)
        let kept = [keptMeal("Snack", number: 2, time: "10:00", in: plan)]
        let slots = [slot(2, "Snack", "10:30"), slot(3, "Snack", "15:30")]
        XCTAssertEqual(PlanRebuild.occupiedSlots(kept: kept, slots: slots), [0])
    }

    func testChangedMealCountDoesNotDropADifferentDishByNumber() {
        let plan = WeeklyMealPlan(startDate: monday, endDate: monday)
        // Kept Lunch was meal #2; the new plan has a Snack as #2 and Lunch as #3.
        let kept = [keptMeal("Lunch", number: 2, time: "12:30", in: plan)]
        let slots = [slot(1, "Breakfast", "08:00"), slot(2, "Snack", "10:30"), slot(3, "Lunch", "12:30")]
        XCTAssertEqual(PlanRebuild.occupiedSlots(kept: kept, slots: slots), [2])
    }

    func testUntypedNamesFallBackToMealNumber() {
        let plan = WeeklyMealPlan(startDate: monday, endDate: monday)
        let kept = [keptMeal("Meal 2", number: 2, time: "13:00", in: plan)]
        let slots = [slot(1, "Meal 1", "08:00"), slot(2, "Meal 2", "13:30"), slot(3, "Meal 3", "19:00")]
        XCTAssertEqual(PlanRebuild.occupiedSlots(kept: kept, slots: slots), [1])
    }

    func testNoPlanYetMidWeekBuildsOnlyFromToday() async throws {
        let rebuilt = try await rebuild()
        XCTAssertEqual(meals(of: rebuilt, offset: 0).count, 0)
        XCTAssertEqual(meals(of: rebuilt, offset: 1).count, 0)
        XCTAssertEqual(meals(of: rebuilt, offset: 2).count, 3)
        XCTAssertEqual(meals(of: rebuilt, offset: 6).count, 3)
        XCTAssertEqual(rebuilt.startDate, monday, "weekStartDate stays the Monday")
    }

    func testNewWeekArchivesTheOldPlanAndStartsFresh() async throws {
        let oldPlan = seedWeek()
        addMeal(oldPlan, dayOffset: 0, number: 1, name: "Breakfast", kcal: 500, status: .eaten, baseline: 500)
        try context.save()
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)!

        let fresh = try await rebuild(weekStart: nextMonday, now: nextMonday)

        XCTAssertNotEqual(fresh.id, oldPlan.id)
        XCTAssertTrue(oldPlan.isArchived)
        XCTAssertFalse(oldPlan.isActive)
        XCTAssertEqual((fresh.meals ?? []).count, 21, "Monday build: the whole week")
        XCTAssertEqual(allPlans().filter(\.isActive).count, 1)
        // Last week's eaten meal is still there for history.
        XCTAssertEqual(oldPlan.meals?.count, 1)
    }

    func testCanonicalMealsHaveNoDuplicatesAfterRebuild() async throws {
        let plan = seedWeek()
        addMeal(plan, dayOffset: 2, number: 1, name: "Breakfast", kcal: 500, status: .eaten, baseline: 500)
        addMeal(plan, dayOffset: 2, number: 2, name: "Lunch", kcal: 700)
        try context.save()

        _ = try await rebuild()
        _ = try await rebuild() // twice in a row

        let canonical = CanonicalMeals.meals(on: now, in: context)
        XCTAssertEqual(canonical.count, 3)
        XCTAssertEqual(Set(canonical.map(\.mealNumber)), [1, 2, 3])
        XCTAssertEqual(CanonicalMeals.eatenMeals(on: now, in: context).count, 1)
    }

    func testEatenMealHistorySeesPastAndTodayAfterRebuild() async throws {
        let plan = seedWeek()
        addMeal(plan, dayOffset: 0, number: 1, name: "Breakfast", kcal: 500, status: .eaten, baseline: 500)
        addMeal(plan, dayOffset: 2, number: 1, name: "Breakfast", kcal: 500, status: .eaten, baseline: 500)
        try context.save()

        _ = try await rebuild()

        let eaten = EatenMealHistory.canonical(
            (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? [], now: now
        )
        XCTAssertEqual(eaten.count, 2, "Monday's and today's eaten breakfasts both still count")
    }

    // MARK: - Fit

    func testFitTrimsWhenTheDayIsAlreadyOverEaten() {
        let plan = WeeklyMealPlan(startDate: monday, endDate: monday)
        let lunch = PlannedMeal(
            dayDate: monday, mealNumber: 2, mealName: "Lunch",
            foods: [PlannedFood(name: "x", quantityGrams: 300, calories: 800, proteinG: 60, carbsG: 80, fatG: 20)],
            totalCalories: 800, totalProtein: 60, totalCarbs: 80, totalFat: 20, mealPlan: plan
        )
        PlanRebuild.fit(
            remaining: [lunch],
            dayTarget: MealMacros(calories: 2000, protein: 150, carbs: 200, fat: 60),
            keptBaseline: MealMacros(calories: 1200, protein: 90, carbs: 120, fat: 40),
            consumed: MealMacros(calories: 1700, protein: 100, carbs: 150, fat: 50)
        )
        XCTAssertEqual(lunch.totalCalories, 300, accuracy: 2, "2000 target − 1700 eaten")
        XCTAssertEqual(lunch.planBaselineCalories ?? 0, 800, accuracy: 0.5, "2000 − 1200 kept baseline")
    }

    func testFitNeverWritesZeroBaselinesWhenTheDayIsAlreadyFull() throws {
        let plan = WeeklyMealPlan(startDate: monday, endDate: monday)
        context.insert(plan)
        let dinner = PlannedMeal(
            dayDate: monday, mealNumber: 3, mealName: "Dinner", scheduledTime: "19:00",
            foods: [PlannedFood(name: "x", quantityGrams: 300, calories: 600, proteinG: 40, carbsG: 60, fatG: 20)],
            totalCalories: 600, totalProtein: 40, totalCarbs: 60, totalFat: 20, mealPlan: plan
        )
        context.insert(dinner)
        // Kept baselines already equal the day target: no room left.
        PlanRebuild.fit(
            remaining: [dinner],
            dayTarget: MealMacros(calories: 2000, protein: 150, carbs: 200, fat: 60),
            keptBaseline: MealMacros(calories: 2000, protein: 150, carbs: 200, fat: 60),
            consumed: MealMacros(calories: 1900, protein: 140, carbs: 190, fat: 55)
        )
        XCTAssertGreaterThan(dinner.planBaselineCalories ?? 0, 0)
        XCTAssertFalse(dinner.isUnplannedLog, "A rebuilt plan meal is never mistaken for an ad-hoc log")

        // Undo of its eaten state reverts it to planned — it is not deleted.
        let env = MealOutcomeService.Env(modelContext: context)
        try MealOutcomeService.markEaten(dinner, pantry: .none, env: env)
        let snap = try MealOutcomeService.undo(dinner, env: env)
        XCTAssertEqual(snap.kind, .revertedToPlanned)
        XCTAssertEqual(dinner.status, .planned)
    }

    func testRebuildPostsWillBeRemovedForEachReplacedMeal() async throws {
        let plan = seedWeek()
        let doomed = addMeal(plan, dayOffset: 2, number: 2, name: "Lunch", kcal: 700)
        let doomedID = doomed.id
        try context.save()

        var removed: [UUID] = []
        let token = NotificationCenter.default.addObserver(
            forName: .tempoMealWillBeRemoved, object: nil, queue: nil
        ) { note in
            if let id = note.userInfo?["id"] as? UUID {
                removed.append(id)
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        _ = try await rebuild()

        XCTAssertTrue(removed.contains(doomedID))
    }
}
