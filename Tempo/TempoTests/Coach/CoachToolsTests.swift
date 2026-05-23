//
// CoachToolsTests.swift
// Tempo
//
// Created by Tempo on 20/05/2026.
//
// Unit tests for the Coach agent's tool implementations. Each test runs
// against an in-memory SwiftData container with a focused set of models.
// Notification side effects are verified via a `MockNotificationService`
// that records every call.
//
// Per `.plans/coach-agent-plan.md` Phase 3.12.

import Foundation
@testable import Tempo
import SwiftData
import Testing

// MARK: - Test container

@MainActor
private func makeCoachTestContainer() throws -> ModelContainer {
    let schema = Schema([
        // Coach
        LearnedPreference.self,
        // Nutrition (touched by every meal-related tool)
        PlannedMeal.self,
        WeeklyMealPlan.self,
        MealPreset.self,
        MealFoodItem.self,
        MealLog.self,
        NutritionTarget.self,
        DietaryProfile.self,
        Recipe.self,
        RecipeIngredient.self,
        RecipeStep.self,
        CachedFood.self,
        MealFeedback.self,
        PantryItem.self,
        Receipt.self,
        ReceiptLineItem.self,
        GroceryList.self,
        GroceryListItem.self,
        // User
        UserProfile.self,
        UserSettings.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - Mock NotificationService (records every call)

@MainActor
final class CoachToolsMockNotifications: NotificationServiceProtocol, @unchecked Sendable {
    struct Call: Equatable {
        let kind: String
        let mealID: UUID?
    }

    private(set) var calls: [Call] = []
    func reset() { calls = [] }

    func cancelDefrostReminders(forMealID mealID: UUID) {
        calls.append(Call(kind: "cancelDefrost", mealID: mealID))
    }

    func cancelPrepStartReminder(forMealID mealID: UUID) {
        calls.append(Call(kind: "cancelPrepStart", mealID: mealID))
    }

    func cancelOverdueMealReminder(forMealID mealID: UUID) {
        calls.append(Call(kind: "cancelOverdue", mealID: mealID))
    }

    func scheduleMealReminder(mealName _: String, time _: Date) {
        calls.append(Call(kind: "scheduleMealReminder", mealID: nil))
    }

    func schedulePrepStartReminder(mealID: UUID, mealName _: String, prepStartDate _: Date) {
        calls.append(Call(kind: "schedulePrepStart", mealID: mealID))
    }

    func scheduleDefrostReminder(
        mealID: UUID,
        ingredientID _: UUID,
        ingredientName _: String,
        mealName _: String,
        leadTimeHours _: Int,
        fireDate _: Date
    ) {
        calls.append(Call(kind: "scheduleDefrost", mealID: mealID))
    }

    func scheduleOverdueMealReminder(
        mealID: UUID,
        mealName _: String,
        scheduledTime _: Date,
        lateMinutes _: Int
    ) {
        calls.append(Call(kind: "scheduleOverdue", mealID: mealID))
    }

    func cancelCategory(_: String) {}

    // The rest of the protocol — no-ops for these tests.
    func requestAuthorization() async throws -> Bool { true }
    func scheduleMorningBriefing(at _: Date, body _: String) {}
    func scheduleAccountabilityNudge(tier _: Int, body _: String, at _: Date) {}
    func cancelAll() {}
    func pendingRequestCount() async -> Int { 0 }
}

// MARK: - Test fixtures

@MainActor
private func todayStart(_ calendar: Calendar = .current) -> Date {
    calendar.startOfDay(for: Date())
}

@MainActor
private func makePlannedMeal(
    mealNumber: Int,
    name: String,
    scheduledTime: String,
    calories: Double = 600,
    status: MealStatus = .planned,
    in context: ModelContext
) -> PlannedMeal {
    let meal = PlannedMeal(
        dayDate: todayStart(),
        mealNumber: mealNumber,
        mealName: name,
        scheduledTime: scheduledTime,
        foods: [],
        totalCalories: calories,
        totalProtein: 40,
        totalCarbs: 60,
        totalFat: 15,
        status: status
    )
    context.insert(meal)
    return meal
}

@MainActor
private func makeActiveWeeklyPlan(
    dayTypeForToday: DayType = .strength,
    in context: ModelContext
) -> WeeklyMealPlan {
    let calendar = Calendar.current
    let today = todayStart()
    let weekday = calendar.component(.weekday, from: today)
    let plan = WeeklyMealPlan(
        startDate: today,
        endDate: calendar.date(byAdding: .day, value: 6, to: today)!,
        dayTypeAssignments: [weekday: dayTypeForToday.rawValue],
        isActive: true
    )
    context.insert(plan)
    return plan
}

// MARK: - recordPreference

@MainActor
@Suite("CoachTools.recordPreference")
struct RecordPreferenceTests {
    @Test func persists_with_explicit_source() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let convID = UUID()

        let out = try CoachTools.recordPreference(
            text: "  Nicola prefers dinner before 9pm weekdays.  ",
            subject: LearnedPreferenceSubject.mealTimingDinner,
            confidence: 0.85,
            conversationID: convID,
            turnIndex: 3,
            modelContext: ctx
        )

        #expect(out.citedPreferenceIDs.count == 1)
        #expect(out.summary.contains("dinner before 9pm"))

        let stored = try ctx.fetch(FetchDescriptor<LearnedPreference>())
        #expect(stored.count == 1)
        #expect(stored[0].source == .explicit)
        #expect(stored[0].sourceConversationID == convID)
        #expect(stored[0].sourceTurnIndex == 3)
        #expect(stored[0].text == "Nicola prefers dinner before 9pm weekdays.") // trimmed
        #expect(abs(stored[0].confidence - 0.85) < 0.001)
    }

    @Test func clamps_confidence_to_valid_range() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)

        let out = try CoachTools.recordPreference(
            text: "User loves carbs.",
            subject: "meal_content.cuisine",
            confidence: 1.7, // out of range
            conversationID: nil,
            turnIndex: nil,
            modelContext: ctx
        )

        let stored = try ctx.fetch(FetchDescriptor<LearnedPreference>())
        #expect(stored.count == 1)
        #expect(stored[0].confidence == 1.0)
        #expect(out.citedPreferenceIDs == [stored[0].id])
    }
}

// MARK: - updatePreference

@MainActor
@Suite("CoachTools.updatePreference")
struct UpdatePreferenceTests {
    @Test func deactivate_marks_inactive() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let pref = LearnedPreference(
            text: "Old claim",
            subject: "meal_timing.breakfast",
            confidence: 0.7,
            source: .explicit
        )
        ctx.insert(pref)
        try ctx.save()

        _ = try CoachTools.updatePreference(
            prefID: pref.id,
            action: .deactivate,
            modelContext: ctx
        )

        #expect(pref.isActive == false)
        #expect(pref.isRetrievable == false)
    }

    @Test func keepClarifyScope_updates_text_and_verifies() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let pref = LearnedPreference(
            text: "Skips breakfast",
            subject: "meal_timing.breakfast",
            confidence: 0.6,
            source: .observed
        )
        ctx.insert(pref)
        try ctx.save()

        _ = try CoachTools.updatePreference(
            prefID: pref.id,
            action: .keepClarifyScope,
            newText: "Skips breakfast on weekdays only",
            modelContext: ctx
        )

        #expect(pref.text == "Skips breakfast on weekdays only")
        #expect(pref.userVerified == true)
        #expect(pref.source == .userVerified)
        #expect(pref.confidence == 1.0)
    }

    @Test func supersede_without_replacement_deactivates() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let pref = LearnedPreference(
            text: "x",
            subject: "x",
            confidence: 0.5,
            source: .explicit
        )
        ctx.insert(pref)
        try ctx.save()

        _ = try CoachTools.updatePreference(
            prefID: pref.id,
            action: .supersede,
            supersededByID: nil,
            modelContext: ctx
        )

        #expect(pref.isActive == false)
    }

    @Test func supersede_with_replacement_wires_edge() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let old = LearnedPreference(
            text: "Eats no breakfast",
            subject: "meal_timing.breakfast",
            confidence: 0.9,
            source: .explicit
        )
        let new = LearnedPreference(
            text: "Eats breakfast at 8am now",
            subject: "meal_timing.breakfast",
            confidence: 0.8,
            source: .explicit
        )
        ctx.insert(old); ctx.insert(new); try ctx.save()

        _ = try CoachTools.updatePreference(
            prefID: old.id,
            action: .supersede,
            supersededByID: new.id,
            modelContext: ctx
        )

        #expect(old.contradictedByID == new.id)
        #expect(old.supersededAt != nil)
        #expect(old.isRetrievable == false) // contradictedBy excludes from retrieval
        #expect(new.isRetrievable == true)
    }

    @Test func markOneOff_lowers_confidence() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let pref = LearnedPreference(
            text: "x",
            subject: "x",
            confidence: 0.7,
            source: .observed,
            evidenceCount: 3
        )
        ctx.insert(pref)
        try ctx.save()

        _ = try CoachTools.updatePreference(
            prefID: pref.id,
            action: .markOneOff,
            modelContext: ctx
        )

        #expect(pref.evidenceCount == 2)
        #expect(abs(pref.confidence - 0.6) < 0.001)
    }

    @Test func unknown_id_throws() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let bogus = UUID()
        do {
            _ = try CoachTools.updatePreference(
                prefID: bogus,
                action: .deactivate,
                modelContext: ctx
            )
            Issue.record("Expected throw")
        } catch CoachToolError.preferenceNotFound(let id) {
            #expect(id == bogus)
        }
    }
}

// MARK: - askUser

@MainActor
@Suite("CoachTools.askUser")
struct AskUserTests {
    @Test func returns_pending_question_with_choices() {
        let out = CoachTools.askUser(
            question: "  Want me to push dinner to 9pm?  ",
            choices: ["Yes", "No, leave it"]
        )
        #expect(out.pendingQuestion != nil)
        #expect(out.pendingQuestion?.question == "Want me to push dinner to 9pm?")
        #expect(out.pendingQuestion?.choices == ["Yes", "No, leave it"])
        #expect(out.summary == "Want me to push dinner to 9pm?")
    }

    @Test func no_choices_means_free_text() {
        let out = CoachTools.askUser(question: "What time do you get home?", choices: nil)
        #expect(out.pendingQuestion?.choices == nil)
    }
}

// MARK: - shiftBedtime

@MainActor
@Suite("CoachTools.shiftBedtime")
struct ShiftBedtimeTests {
    @Test func valid_time_succeeds() throws {
        let out = try CoachTools.shiftBedtime(date: Date(), newBedtimeHHmm: "00:30")
        #expect(out.summary.contains("00:30"))
        #expect(out.sideEffects.first?.contains("v1") == true)
    }

    @Test func invalid_time_throws() {
        do {
            _ = try CoachTools.shiftBedtime(date: Date(), newBedtimeHHmm: "25:99")
            Issue.record("Expected throw")
        } catch CoachToolError.invalidTimeFormat {
            // pass
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }
}

// MARK: - moveMeal

@MainActor
@Suite("CoachTools.moveMeal")
struct MoveMealTests {
    @Test func moves_target_and_shifts_downstream() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let breakfast = makePlannedMeal(mealNumber: 1, name: "Breakfast", scheduledTime: "07:30", in: ctx)
        let lunch = makePlannedMeal(mealNumber: 2, name: "Lunch", scheduledTime: "12:30", in: ctx)
        let dinner = makePlannedMeal(mealNumber: 3, name: "Dinner", scheduledTime: "19:30", in: ctx)
        let snack = makePlannedMeal(mealNumber: 4, name: "Snack", scheduledTime: "21:00", in: ctx)
        try ctx.save()

        let notifs = CoachToolsMockNotifications()
        let out = try CoachTools.moveMeal(
            mealID: lunch.id,
            newTimeHHmm: "13:30",
            notifications: notifs,
            modelContext: ctx
        )

        // Target meal moved.
        #expect(lunch.scheduledTime == "13:30")
        // Earlier meals untouched.
        #expect(breakfast.scheduledTime == "07:30")
        // Downstream meals shifted by +1h.
        #expect(dinner.scheduledTime == "20:30")
        #expect(snack.scheduledTime == "22:00")
        // Effects list has all 3 moved meals.
        #expect(out.sideEffects.count == 3)
        // Notifications were cancelled + rescheduled for moved meals.
        let cancelKinds = notifs.calls.filter { $0.kind.hasPrefix("cancel") }
        #expect(cancelKinds.count >= 9) // 3 cancel kinds × 3 moved meals
    }

    @Test func meal_already_eaten_throws() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let m = makePlannedMeal(
            mealNumber: 1, name: "Breakfast", scheduledTime: "07:30",
            status: .eaten, in: ctx
        )
        try ctx.save()

        do {
            _ = try CoachTools.moveMeal(
                mealID: m.id,
                newTimeHHmm: "08:00",
                notifications: nil,
                modelContext: ctx
            )
            Issue.record("Expected throw")
        } catch CoachToolError.mealAlreadyEaten(let id) {
            #expect(id == m.id)
        }
    }

    @Test func unknown_meal_throws() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let bogus = UUID()
        do {
            _ = try CoachTools.moveMeal(
                mealID: bogus,
                newTimeHHmm: "08:00",
                notifications: nil,
                modelContext: ctx
            )
            Issue.record("Expected throw")
        } catch CoachToolError.mealNotFound(let id) {
            #expect(id == bogus)
        }
    }
}

// MARK: - swapDayType

@MainActor
@Suite("CoachTools.swapDayType")
struct SwapDayTypeTests {
    @Test func updates_assignment_and_scales_macros() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let plan = makeActiveWeeklyPlan(dayTypeForToday: .strength, in: ctx)
        let dinner = makePlannedMeal(
            mealNumber: 3, name: "Dinner", scheduledTime: "19:30",
            calories: 800, in: ctx
        )
        dinner.mealPlan = plan
        try ctx.save()

        _ = try CoachTools.swapDayType(
            date: Date(),
            newType: .soccer,
            scaleMacros: true,
            modelContext: ctx
        )

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        #expect(plan.dayTypeAssignments[weekday] == "soccer")
        // strength=1.00, soccer=1.15 → expect 800 × 1.15 = 920
        #expect(abs(dinner.totalCalories - 920) < 1.0)
    }

    @Test func no_active_plan_throws() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        do {
            _ = try CoachTools.swapDayType(
                date: Date(),
                newType: .soccer,
                scaleMacros: false,
                modelContext: ctx
            )
            Issue.record("Expected throw")
        } catch CoachToolError.noActivePlan {
            // pass
        }
    }

    @Test func no_change_when_same_type() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        _ = makeActiveWeeklyPlan(dayTypeForToday: .strength, in: ctx)
        let dinner = makePlannedMeal(
            mealNumber: 3, name: "Dinner", scheduledTime: "19:30",
            calories: 800, in: ctx
        )
        try ctx.save()

        let out = try CoachTools.swapDayType(
            date: Date(),
            newType: .strength,
            scaleMacros: true,
            modelContext: ctx
        )
        // No scaling applied.
        #expect(dinner.totalCalories == 800)
        #expect(out.sideEffects.isEmpty)
    }
}

// MARK: - skipMeal

@MainActor
@Suite("CoachTools.skipMeal")
struct SkipMealTests {
    @Test func marks_skipped_and_cancels_notifications() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let lunch = makePlannedMeal(
            mealNumber: 2, name: "Lunch", scheduledTime: "12:30",
            in: ctx
        )
        try ctx.save()

        let notifs = CoachToolsMockNotifications()
        _ = try CoachTools.skipMeal(
            mealID: lunch.id,
            notifications: notifs,
            modelContext: ctx
        )

        #expect(lunch.status == .skipped)
        let kinds = Set(notifs.calls.map(\.kind))
        #expect(kinds.contains("cancelDefrost"))
        #expect(kinds.contains("cancelPrepStart"))
        #expect(kinds.contains("cancelOverdue"))
    }

    @Test func eaten_meal_throws() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let m = makePlannedMeal(
            mealNumber: 1, name: "Breakfast", scheduledTime: "07:30",
            status: .eaten, in: ctx
        )
        try ctx.save()

        do {
            _ = try CoachTools.skipMeal(
                mealID: m.id,
                notifications: nil,
                modelContext: ctx
            )
            Issue.record("Expected throw")
        } catch CoachToolError.mealAlreadyEaten {
            // pass
        }
    }
}

// MARK: - swapToQuickerMeal

@MainActor
@Suite("CoachTools.swapToQuickerMeal")
struct SwapToQuickerMealTests {
    @Test func returns_up_to_three_alternatives() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let dinner = makePlannedMeal(
            mealNumber: 3, name: "Dinner", scheduledTime: "19:30",
            calories: 700, in: ctx
        )
        // Add 5 recipes; 3 fast, 2 slow.
        for (i, mins) in [10, 15, 18, 45, 60].enumerated() {
            let r = Recipe(
                name: "Recipe \(i)",
                servings: 1,
                prepMinutes: mins / 2,
                cookMinutes: mins / 2,
                totalCalories: 700 + Double(i * 20),
                totalProteinGrams: 40,
                totalCarbsGrams: 70,
                totalFatGrams: 15
            )
            ctx.insert(r)
        }
        try ctx.save()

        let out = try CoachTools.swapToQuickerMeal(
            mealID: dinner.id,
            maxPrepMin: 20,
            modelContext: ctx
        )

        // 3 recipes are <= 20min; expect 3 results.
        #expect(out.sideEffects.count == 3)
        #expect(out.summary.contains("3 quicker alternatives"))
    }

    @Test func no_candidates_throws() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let dinner = makePlannedMeal(
            mealNumber: 3, name: "Dinner", scheduledTime: "19:30",
            in: ctx
        )
        // Single slow recipe.
        let r = Recipe(
            name: "Slow Stew",
            servings: 1,
            prepMinutes: 30,
            cookMinutes: 60,
            totalCalories: 700,
            totalProteinGrams: 40,
            totalCarbsGrams: 70,
            totalFatGrams: 15
        )
        ctx.insert(r)
        try ctx.save()

        do {
            _ = try CoachTools.swapToQuickerMeal(
                mealID: dinner.id,
                maxPrepMin: 20,
                modelContext: ctx
            )
            Issue.record("Expected throw")
        } catch CoachToolError.noSuitableAlternative {
            // pass
        }
    }
}

// MARK: - insertActivity

@MainActor
@Suite("CoachTools.insertActivity")
struct InsertActivityTests {
    @Test func soccer_with_day_type_change_scales_macros() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        let plan = makeActiveWeeklyPlan(dayTypeForToday: .strength, in: ctx)
        let lunch = makePlannedMeal(mealNumber: 2, name: "Lunch", scheduledTime: "12:30", calories: 700, in: ctx)
        let dinner = makePlannedMeal(mealNumber: 3, name: "Dinner", scheduledTime: "19:30", calories: 800, in: ctx)
        lunch.mealPlan = plan
        dinner.mealPlan = plan
        try ctx.save()

        // Soccer 19:00–20:30, dinner should move to 21:00 (30min post-game).
        let out = try CoachTools.insertActivity(
            name: "Soccer match",
            date: Date(),
            startMin: 19 * 60,
            endMin: 20 * 60 + 30,
            dayImpact: .changesDayType(.soccer),
            nearestMealNumber: 3,
            mealPlacement: .afterActivity(bufferMin: 30),
            notifications: nil,
            modelContext: ctx
        )

        #expect(dinner.scheduledTime == "21:00")
        #expect(abs(dinner.totalCalories - 920) < 1.0) // 800 × 1.15
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        #expect(plan.dayTypeAssignments[weekday] == "soccer")
        #expect(out.sideEffects.count >= 2)
    }

    @Test func invalid_window_throws() throws {
        let container = try makeCoachTestContainer()
        let ctx = ModelContext(container)
        do {
            _ = try CoachTools.insertActivity(
                name: "Bad",
                date: Date(),
                startMin: 1500, // > 1440
                endMin: 1600,
                dayImpact: .shiftsMealsOnly,
                nearestMealNumber: nil,
                mealPlacement: .afterActivity(bufferMin: 30),
                notifications: nil,
                modelContext: ctx
            )
            Issue.record("Expected throw")
        } catch CoachToolError.invalidActivityWindow {
            // pass
        }
    }
}

// MARK: - LearnedPreference helpers

@MainActor
@Suite("LearnedPreference lifecycle")
struct LearnedPreferenceTests {
    @Test func reinforce_caps_confidence_at_1() {
        let p = LearnedPreference(text: "x", subject: "x", confidence: 0.98, source: .explicit)
        p.markReinforced(by: 0.5)
        #expect(p.confidence == 1.0)
        #expect(p.evidenceCount == 2)
    }

    @Test func decay_explicit_is_slower_than_observed() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let explicit = LearnedPreference(
            text: "x", subject: "x", confidence: 0.8,
            source: .explicit, lastSeenAt: yesterday
        )
        let observed = LearnedPreference(
            text: "y", subject: "y", confidence: 0.8,
            source: .observed, lastSeenAt: yesterday
        )
        explicit.applyDailyDecay()
        observed.applyDailyDecay()
        #expect(explicit.confidence > observed.confidence)
    }

    @Test func verified_is_immune_to_decay() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let p = LearnedPreference(
            text: "x", subject: "x", confidence: 1.0,
            source: .userVerified, lastSeenAt: yesterday, userVerified: true
        )
        p.applyDailyDecay()
        #expect(p.confidence == 1.0)
    }

    @Test func decay_below_floor_deactivates() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let p = LearnedPreference(
            text: "x", subject: "x", confidence: 0.205,
            source: .observed, lastSeenAt: yesterday
        )
        p.applyDailyDecay() // 0.205 × 0.97 = 0.199 → below floor
        #expect(p.isActive == false)
    }
}
