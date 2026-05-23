//
// CoachContextAssemblerTests.swift
// Tempo
//
// Created by Tempo on 20/05/2026.
//
// Tests for the assembler that composes the Coach's per-turn memory
// snapshot. We assert: (a) bands render correctly from in-memory fixtures,
// (b) truncation respects the token budget, (c) renderable output is
// deterministic for the same input.
//
// Per `.plans/coach-agent-plan.md` Phase 5.

import Foundation
@testable import Tempo
import SwiftData
import Testing

@MainActor
private func makeAssemblerContainer() throws -> ModelContainer {
    let schema = Schema([
        LearnedPreference.self,
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
        UserProfile.self,
        UserSettings.self,
    ])
    return try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
}

@MainActor
private func seedProfile(_ context: ModelContext) {
    let profile = UserProfile(
        appleID: "test",
        username: "tester",
        displayName: "Nicola",
        identityLabel: "Student / Athlete",
        timezone: "America/New_York",
        weightKg: 78,
        heightCm: 182,
        age: 22
    )
    context.insert(profile)
}

@MainActor
struct CoachContextAssemblerBandTests {

    @Test func identityBandIncludesProfileFacts() throws {
        let container = try makeAssemblerContainer()
        seedProfile(container.mainContext)
        try container.mainContext.save()
        let assembler = CoachContextAssembler(context: container.mainContext)
        let band = assembler.identityBand()
        #expect(band.contains("Nicola"))
        #expect(band.contains("22"))     // age
        #expect(band.contains("78kg"))
        #expect(band.contains("America/New_York"))
    }

    @Test func identityBandHandlesMissingProfile() throws {
        let container = try makeAssemblerContainer()
        let assembler = CoachContextAssembler(context: container.mainContext)
        let band = assembler.identityBand()
        #expect(band.contains("no profile"))
    }

    @Test func preferencesBandSurfacesActiveOnly() throws {
        let container = try makeAssemblerContainer()
        let ctx = container.mainContext
        let active = LearnedPreference(
            text: "Dinner at 19:30",
            subject: LearnedPreferenceSubject.mealTimingDinner,
            confidence: 0.8,
            source: .explicit
        )
        let inactive = LearnedPreference(
            text: "Old dinner pref",
            subject: LearnedPreferenceSubject.mealTimingDinner,
            confidence: 0.5,
            source: .observed,
            isActive: false
        )
        ctx.insert(active)
        ctx.insert(inactive)
        try ctx.save()
        let assembler = CoachContextAssembler(context: ctx)
        let band = assembler.preferencesBand(userMessage: "what time is dinner?")
        #expect(band.contains("Dinner at 19:30"))
        #expect(!band.contains("Old dinner pref"))
    }

    @Test func todayBandShowsPlannedAndLogged() throws {
        let container = try makeAssemblerContainer()
        let ctx = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())
        ctx.insert(PlannedMeal(
            dayDate: today,
            mealName: "Breakfast",
            scheduledTime: "08:00",
            totalCalories: 500,
            totalProtein: 30
        ))
        ctx.insert(MealLog(
            mealType: .breakfast,
            loggedAt: today.addingTimeInterval(8 * 3600 + 15 * 60),
            totalCalories: 520,
            totalProtein: 32,
            totalCarbs: 50,
            totalFat: 12,
            totalFiber: 4,
            source: .manual
        ))
        try ctx.save()
        let band = CoachContextAssembler(context: ctx).todayBand()
        #expect(band.contains("Planned:"))
        #expect(band.contains("Breakfast"))
        #expect(band.contains("Logged:"))
    }

    @Test func lookBackBandSummarizesPriorWeek() throws {
        let container = try makeAssemblerContainer()
        let ctx = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())
        for daysAgo in 1...3 {
            let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today)!
            ctx.insert(MealLog(
                mealType: .lunch,
                loggedAt: day,
                totalCalories: 600,
                totalProtein: 35,
                totalCarbs: 60,
                totalFat: 18,
                totalFiber: 6,
                source: .manual
            ))
        }
        try ctx.save()
        let band = CoachContextAssembler(context: ctx).lookBackBand()
        #expect(band.contains("Last 7 days"))
        #expect(band.contains("kcal"))
    }

    @Test func lookForwardBandSummarizesNextWeek() throws {
        let container = try makeAssemblerContainer()
        let ctx = container.mainContext
        let today = Calendar.current.startOfDay(for: Date())
        for daysAhead in 1...2 {
            let day = Calendar.current.date(byAdding: .day, value: daysAhead, to: today)!
            ctx.insert(PlannedMeal(
                dayDate: day,
                mealName: "Lunch",
                scheduledTime: "13:00",
                totalCalories: 600
            ))
        }
        try ctx.save()
        let band = CoachContextAssembler(context: ctx).lookForwardBand()
        #expect(band.contains("Next 7 days"))
        #expect(band.contains("planned meals"))
    }
}

@MainActor
struct CoachContextAssemblerSnapshotTests {

    @Test func snapshotRespectsTokenBudget() throws {
        let container = try makeAssemblerContainer()
        let ctx = container.mainContext
        seedProfile(ctx)
        for i in 0..<50 {
            ctx.insert(LearnedPreference(
                text: "Preference number \(i) describing a behavior pattern",
                subject: LearnedPreferenceSubject.mealTimingDinner,
                confidence: 0.5,
                source: .observed
            ))
        }
        try ctx.save()
        let assembler = CoachContextAssembler(context: ctx)
        let snapshot = assembler.snapshot(userMessage: "dinner?", tokenBudget: 200)
        #expect(snapshot.estimatedTokens <= 250) // small slop allowed for truncation marker
    }

    @Test func snapshotIsDeterministic() throws {
        let container = try makeAssemblerContainer()
        let ctx = container.mainContext
        seedProfile(ctx)
        ctx.insert(LearnedPreference(
            text: "Dinner at 19:30",
            subject: LearnedPreferenceSubject.mealTimingDinner,
            confidence: 0.8,
            source: .explicit
        ))
        try ctx.save()
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let a = CoachContextAssembler(context: ctx, now: fixed).snapshot(userMessage: "dinner")
        let b = CoachContextAssembler(context: ctx, now: fixed).snapshot(userMessage: "dinner")
        #expect(a == b)
    }

    @Test func truncateAddsTruncationMarker() throws {
        let container = try makeAssemblerContainer()
        let ctx = container.mainContext
        let assembler = CoachContextAssembler(context: ctx)
        let original = (1...30).map { "Line \($0)" }.joined(separator: "\n")
        let truncated = assembler.truncate(original, toTokens: 10)
        #expect(truncated.contains("truncated"))
    }
}
