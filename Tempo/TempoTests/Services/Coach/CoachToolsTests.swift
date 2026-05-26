//
// CoachToolsTests.swift
// Tempo
//
// Coach v2.1 Phase 3 — coverage for all 10 tools.
// Happy paths + edge cases (already-eaten guards, invalid IDs, time-format
// errors, activity-window validation, preference supersession edges).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class CoachToolsTests: XCTestCase {
    // MARK: - Container + fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WeeklyMealPlan.self,
            PlannedMeal.self,
            Recipe.self,
            RecipeIngredient.self,
            RecipeStep.self,
            LearnedPreference.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Sets up an active weekly plan with `mealCount` planned meals for the
    /// given day. Returns (container, context, plan, meals).
    private func makeFixture(
        mealCount: Int = 4,
        on dayDate: Date = Calendar.current.startOfDay(for: Date())
    ) throws -> (ModelContainer, ModelContext, WeeklyMealPlan, [PlannedMeal]) {
        let container = try makeContainer()
        let context = ModelContext(container)
        let plan = WeeklyMealPlan(
            startDate: dayDate,
            endDate: Calendar.current.date(byAdding: .day, value: 6, to: dayDate) ?? dayDate,
            isActive: true
        )
        context.insert(plan)
        let names = ["Breakfast", "Lunch", "Dinner", "Snack"]
        let times = ["07:30", "12:30", "19:30", "16:00"]
        var meals: [PlannedMeal] = []
        for i in 0..<mealCount {
            let meal = PlannedMeal(
                dayDate: dayDate,
                mealNumber: i + 1,
                mealName: names[min(i, 3)],
                scheduledTime: times[min(i, 3)],
                totalCalories: 600,
                totalProtein: 35,
                totalCarbs: 60,
                totalFat: 18
            )
            meal.mealPlan = plan
            context.insert(meal)
            meals.append(meal)
        }
        try context.save()
        return (container, context, plan, meals)
    }

    // MARK: - moveMeal

    func testMoveMeal_updatesScheduledTimeAndMarksModified() throws {
        let (_, context, _, meals) = try makeFixture()
        let lunch = try XCTUnwrap(meals.first { $0.mealNumber == 2 })
        let output = try CoachTools.moveMeal(
            mealID: lunch.id,
            newTimeHHmm: "13:15",
            context: context
        )
        XCTAssertTrue(output.summary.contains("13:15"))
        let reloaded = try CoachToolHelpers.plannedMeal(id: lunch.id, in: context)
        XCTAssertEqual(reloaded.scheduledTime, "13:15")
        XCTAssertEqual(reloaded.status, .modified)
    }

    func testMoveMeal_invalidTimeFormat_throws() throws {
        let (_, context, _, meals) = try makeFixture()
        let lunch = try XCTUnwrap(meals.first { $0.mealNumber == 2 })
        XCTAssertThrowsError(
            try CoachTools.moveMeal(mealID: lunch.id, newTimeHHmm: "25:99", context: context)
        ) { err in
            guard case CoachToolError.invalidTimeFormat = err else {
                return XCTFail("expected .invalidTimeFormat, got \(err)")
            }
        }
    }

    func testMoveMeal_eatenMealRefuses() throws {
        let (_, context, _, meals) = try makeFixture()
        let lunch = try XCTUnwrap(meals.first { $0.mealNumber == 2 })
        lunch.status = .eaten
        try context.save()
        XCTAssertThrowsError(
            try CoachTools.moveMeal(mealID: lunch.id, newTimeHHmm: "13:15", context: context)
        ) { err in
            guard case CoachToolError.mealAlreadyLogged = err else {
                return XCTFail("expected .mealAlreadyLogged, got \(err)")
            }
        }
    }

    func testMoveMeal_unknownIDThrows() throws {
        let (_, context, _, _) = try makeFixture()
        XCTAssertThrowsError(
            try CoachTools.moveMeal(mealID: UUID(), newTimeHHmm: "13:15", context: context)
        ) { err in
            guard case CoachToolError.mealNotFound = err else {
                return XCTFail("expected .mealNotFound, got \(err)")
            }
        }
    }

    // MARK: - swapDayType

    func testSwapDayType_changesAssignmentAndReturnsSummary() throws {
        let (_, context, plan, _) = try makeFixture()
        var assignments = plan.dayTypeAssignments
        assignments[0] = DayType.rest.rawValue // Monday
        plan.dayTypeAssignments = assignments
        try context.save()

        // Force the fixture day to be Monday so dayIndex0Mon == 0.
        let monday = mondayDate()

        let output = try CoachTools.swapDayType(
            date: monday,
            newType: .strength,
            scaleMacros: false,
            caloriesMultiplier: 1.0,
            context: context
        )
        XCTAssertTrue(output.summary.contains("Rest"))
        XCTAssertTrue(output.summary.contains("Strength"))
        let reloaded = plan.dayTypeAssignments[0]
        XCTAssertEqual(reloaded, DayType.strength.rawValue)
    }

    func testSwapDayType_sameTypeIsNoOp() throws {
        let (_, context, plan, _) = try makeFixture()
        var assignments = plan.dayTypeAssignments
        assignments[0] = DayType.cardio.rawValue
        plan.dayTypeAssignments = assignments
        try context.save()

        let output = try CoachTools.swapDayType(
            date: mondayDate(),
            newType: .cardio,
            scaleMacros: false,
            caloriesMultiplier: 1.0,
            context: context
        )
        XCTAssertTrue(output.summary.localizedCaseInsensitiveContains("no change"))
    }

    func testSwapDayType_scaleMacrosByRatio() throws {
        // Pin the fixture to Monday so dayIndex0Mon == 0.
        let monday = mondayDate()
        let (_, context, _, meals) = try makeFixture(on: monday)

        let originalCal = meals[0].totalCalories
        let originalP = meals[0].totalProtein
        _ = try CoachTools.swapDayType(
            date: monday,
            newType: .strength,
            scaleMacros: true,
            caloriesMultiplier: 1.20,
            context: context
        )
        XCTAssertEqual(meals[0].totalCalories, originalCal * 1.20, accuracy: 0.001)
        XCTAssertEqual(meals[0].totalProtein, originalP * 1.20, accuracy: 0.001)
    }

    // MARK: - skipMeal

    func testSkipMeal_marksSkipped() throws {
        let (_, context, _, meals) = try makeFixture()
        let snack = try XCTUnwrap(meals.first { $0.mealNumber == 4 })
        let output = try CoachTools.skipMeal(mealID: snack.id, context: context)
        XCTAssertTrue(output.summary.contains("Snack"))
        XCTAssertEqual(snack.status, .skipped)
    }

    func testSkipMeal_eatenMealRefuses() throws {
        let (_, context, _, meals) = try makeFixture()
        let breakfast = try XCTUnwrap(meals.first { $0.mealNumber == 1 })
        breakfast.status = .eaten
        try context.save()
        XCTAssertThrowsError(try CoachTools.skipMeal(mealID: breakfast.id, context: context)) { err in
            guard case CoachToolError.mealAlreadyLogged = err else {
                return XCTFail("expected .mealAlreadyLogged, got \(err)")
            }
        }
    }

    // MARK: - swapToQuickerMeal

    func testSwapToQuicker_returnsTopThreeUnderCap() throws {
        let (_, context, _, meals) = try makeFixture()
        let dinner = try XCTUnwrap(meals.first { $0.mealNumber == 3 })

        // Seed 4 recipes: 3 under cap, 1 over.
        let r1 = Recipe(name: "Quick Bowl", mealType: .any, prepMinutes: 5, cookMinutes: 5, totalCalories: 600, totalProteinGrams: 35, totalCarbsGrams: 60, totalFatGrams: 18)
        let r2 = Recipe(name: "Stir Fry", mealType: .any, prepMinutes: 10, cookMinutes: 5, totalCalories: 550, totalProteinGrams: 30, totalCarbsGrams: 55, totalFatGrams: 16)
        let r3 = Recipe(name: "Wrap", mealType: .any, prepMinutes: 5, cookMinutes: 0, totalCalories: 620, totalProteinGrams: 32, totalCarbsGrams: 65, totalFatGrams: 18)
        let r4 = Recipe(name: "Slow Roast", mealType: .any, prepMinutes: 20, cookMinutes: 60, totalCalories: 600, totalProteinGrams: 35, totalCarbsGrams: 60, totalFatGrams: 18)
        for recipe in [r1, r2, r3, r4] { context.insert(recipe) }
        try context.save()

        let output = try CoachTools.swapToQuickerMeal(mealID: dinner.id, maxPrepMin: 20, context: context)
        XCTAssertEqual(output.sideEffects.count, 3, "should return 3 options")
        XCTAssertFalse(output.sideEffects.contains { $0.contains("Slow Roast") })
        // Quick Bowl is macro-identical to dinner — should rank first.
        XCTAssertTrue(output.sideEffects[0].contains("Quick Bowl"))
    }

    func testSwapToQuicker_invalidMaxPrepThrows() throws {
        let (_, context, _, meals) = try makeFixture()
        let dinner = try XCTUnwrap(meals.first { $0.mealNumber == 3 })
        XCTAssertThrowsError(
            try CoachTools.swapToQuickerMeal(mealID: dinner.id, maxPrepMin: 0, context: context)
        ) { err in
            guard case CoachToolError.invalidMaxPrepMinutes = err else {
                return XCTFail("expected .invalidMaxPrepMinutes, got \(err)")
            }
        }
    }

    func testSwapToQuicker_noCandidatesGracefulMessage() throws {
        let (_, context, _, meals) = try makeFixture()
        let dinner = try XCTUnwrap(meals.first { $0.mealNumber == 3 })
        let output = try CoachTools.swapToQuickerMeal(mealID: dinner.id, maxPrepMin: 15, context: context)
        XCTAssertTrue(output.summary.contains("No recipes"))
    }

    // MARK: - insertActivity

    func testInsertActivity_invalidWindowThrows() throws {
        let (_, context, _, _) = try makeFixture()
        XCTAssertThrowsError(
            try CoachTools.insertActivity(
                name: "soccer",
                date: Date(),
                startMin: 1200,
                endMin: 600, // before start — invalid
                dayImpact: .shiftsMealsOnly,
                nearestMealNumber: 3,
                mealPlacement: .afterActivity(bufferMin: 30),
                context: context
            )
        ) { err in
            guard case CoachToolError.invalidActivityWindow = err else {
                return XCTFail("expected .invalidActivityWindow, got \(err)")
            }
        }
    }

    func testInsertActivity_shiftsMealsOnly_movesNearestMealAfter() throws {
        let monday = mondayDate()
        let (_, context, _, meals) = try makeFixture(on: monday)
        let dinner = try XCTUnwrap(meals.first { $0.mealNumber == 3 })
        // Soccer 19:00–20:30 → dinner pushed to 20:30 + 30min buffer = 21:00.
        let output = try CoachTools.insertActivity(
            name: "soccer",
            date: monday,
            startMin: 19 * 60,
            endMin: 20 * 60 + 30,
            dayImpact: .shiftsMealsOnly,
            nearestMealNumber: 3,
            mealPlacement: .afterActivity(bufferMin: 30),
            context: context
        )
        XCTAssertEqual(dinner.scheduledTime, "21:00")
        XCTAssertTrue(output.summary.contains("soccer"))
    }

    func testInsertActivity_changesDayTypeAndShifts() throws {
        let monday = mondayDate()
        let (_, context, _, meals) = try makeFixture(on: monday)
        let dinner = try XCTUnwrap(meals.first { $0.mealNumber == 3 })
        let output = try CoachTools.insertActivity(
            name: "soccer",
            date: monday,
            startMin: 19 * 60,
            endMin: 20 * 60 + 30,
            dayImpact: .changesDayType(.soccer),
            nearestMealNumber: 3,
            mealPlacement: .afterActivity(bufferMin: 30),
            context: context,
            dayTypeCaloriesMultiplier: 1.0
        )
        XCTAssertEqual(dinner.scheduledTime, "21:00")
        XCTAssertTrue(output.sideEffects.contains { $0.contains("Soccer") || $0.contains("Move") || $0.contains("Day type") })
    }

    // MARK: - shiftBedtime

    func testShiftBedtime_acknowledgement() throws {
        let output = try CoachTools.shiftBedtime(date: Date(), newBedtimeHHmm: "22:30")
        XCTAssertTrue(output.summary.contains("22:30"))
        XCTAssertEqual(output.sideEffects.count, 1)
    }

    func testShiftBedtime_invalidTimeThrows() {
        XCTAssertThrowsError(try CoachTools.shiftBedtime(date: Date(), newBedtimeHHmm: "not-a-time")) { err in
            guard case CoachToolError.invalidTimeFormat = err else {
                return XCTFail("expected .invalidTimeFormat, got \(err)")
            }
        }
    }

    // MARK: - askUser

    func testAskUser_emitsPendingQuestion() {
        let output = CoachTools.askUser(
            question: "Lift Tuesdays still your plan?",
            choices: ["Yes", "No", "Sometimes"]
        )
        XCTAssertNotNil(output.pendingQuestion)
        XCTAssertEqual(output.pendingQuestion?.choices.count, 3)
        XCTAssertEqual(output.summary, "Lift Tuesdays still your plan?")
    }

    // MARK: - updatePreference

    func testUpdatePreference_supersedeMarksInactive() throws {
        let (_, context, _, _) = try makeFixture()
        let pref = LearnedPreference(text: "x", subject: "tone.style", source: .observed, confidence: 0.7)
        context.insert(pref)
        try context.save()

        let newID = UUID()
        _ = try CoachTools.updatePreference(
            prefID: pref.id,
            action: .supersede,
            supersededByID: newID,
            context: context
        )
        XCTAssertFalse(pref.isActive)
        XCTAssertEqual(pref.supersededBy, newID)
    }

    func testUpdatePreference_supersedeWithoutIDDeactivates() throws {
        let (_, context, _, _) = try makeFixture()
        let pref = LearnedPreference(text: "x", subject: "tone.style", source: .observed)
        context.insert(pref)
        try context.save()
        _ = try CoachTools.updatePreference(
            prefID: pref.id,
            action: .supersede,
            context: context
        )
        XCTAssertFalse(pref.isActive)
        XCTAssertNil(pref.supersededBy, "no replacement means no pointer")
    }

    func testUpdatePreference_keepClarifyScope_appliesNewScope() throws {
        let (_, context, _, _) = try makeFixture()
        let pref = LearnedPreference(
            text: "lifts Tuesdays",
            subject: "training.match_days",
            source: .observed,
            scope: .always,
            needsReview: true
        )
        context.insert(pref)
        try context.save()
        _ = try CoachTools.updatePreference(
            prefID: pref.id,
            action: .keepClarifyScope,
            newScope: .weekday,
            context: context
        )
        XCTAssertEqual(pref.scope, .weekday)
        XCTAssertFalse(pref.needsReview)
    }

    func testUpdatePreference_unknownIDThrows() throws {
        let (_, context, _, _) = try makeFixture()
        XCTAssertThrowsError(
            try CoachTools.updatePreference(prefID: UUID(), action: .deactivate, context: context)
        ) { err in
            guard case CoachToolError.preferenceNotFound = err else {
                return XCTFail("expected .preferenceNotFound, got \(err)")
            }
        }
    }

    // MARK: - recordPreference

    func testRecordPreference_persistsRowWithDefaults() throws {
        let (_, context, _, _) = try makeFixture()
        let convID = UUID()
        let output = try CoachTools.recordPreference(
            text: "never eats before 11am",
            subject: "meal_timing.breakfast.skipped",
            source: .explicit,
            polarity: .positive,
            scope: .always,
            conversationID: convID,
            turnIndex: 2,
            context: context
        )
        XCTAssertTrue(output.summary.contains("never eats"))

        let prefs = try context.fetch(FetchDescriptor<LearnedPreference>())
        let row = try XCTUnwrap(prefs.first)
        XCTAssertEqual(row.source, .explicit)
        XCTAssertEqual(row.confidence, 0.9, accuracy: 0.001) // explicit default
        XCTAssertEqual(row.decayRate, 0.98, accuracy: 0.001) // meal_timing.* default
        XCTAssertEqual(row.evidenceConvId, convID)
        XCTAssertEqual(row.evidenceTurnIndex, 2)
    }

    // MARK: - Helpers

    /// Returns the Monday of the current calendar week so swapDayType
    /// tests can reliably hit dayIndex0Mon == 0.
    private func mondayDate() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        // Monday is weekday 2; compute offset.
        let offset = (weekday == 1) ? -6 : (2 - weekday)
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }
}
