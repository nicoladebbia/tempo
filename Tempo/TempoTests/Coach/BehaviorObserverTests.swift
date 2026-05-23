//
// BehaviorObserverTests.swift
// Tempo
//
// Created by Tempo on 20/05/2026.
//
// Unit tests for the nightly behavior observer. Synthetic PlannedMeal +
// MealLog fixtures cover skip detection, late/early time drift, and
// reinforcement of on-time meals. `apply` and persistence go through an
// in-memory ModelContainer.
//
// Per `.plans/coach-agent-plan.md` Phase 4.

import Foundation
@testable import Tempo
import SwiftData
import Testing

@MainActor
private func makeObserverContainer() throws -> ModelContainer {
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

private func dayOffset(_ days: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: Date()))!
}

private func planned(
    name: String,
    daysAgo: Int,
    time: String
) -> PlannedMeal {
    PlannedMeal(
        dayDate: dayOffset(daysAgo),
        mealNumber: 1,
        mealName: name,
        scheduledTime: time,
        foods: [],
        totalCalories: 500,
        totalProtein: 30,
        totalCarbs: 50,
        totalFat: 15,
        status: .planned
    )
}

private func loggedAt(daysAgo: Int, hour: Int, minute: Int, type: MealType) -> MealLog {
    let day = dayOffset(daysAgo)
    let loggedAt = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    return MealLog(
        mealType: type,
        loggedAt: loggedAt,
        totalCalories: 500,
        totalProtein: 30,
        totalCarbs: 50,
        totalFat: 15,
        totalFiber: 5,
        source: .manual
    )
}

@MainActor
struct BehaviorObserverDetectionTests {

    @Test func detectsSkippedDinnerWhenThreeOrMoreOfSevenDaysHaveNoLog() {
        // 7 days planned dinner, only 3 of them logged → 4 skipped.
        let plannedMeals = (1...7).map { planned(name: "Dinner", daysAgo: $0, time: "19:30") }
        let logs = (1...3).map { loggedAt(daysAgo: $0, hour: 19, minute: 30, type: .dinner) }
        let proposals = BehaviorObserver.detectPatterns(planned: plannedMeals, logs: logs)

        let skip = proposals.first { proposal in
            if case let .skip(type, count, _) = proposal.kind, type == "dinner", count >= 3 { return true }
            return false
        }
        #expect(skip != nil)
        #expect(skip?.subject == LearnedPreferenceSubject.mealTimingDinner)
    }

    @Test func detectsLateTimeDriftWhenFourOrMoreDaysAreOver30MinLate() {
        let plannedMeals = (1...7).map { planned(name: "Dinner", daysAgo: $0, time: "19:30") }
        let logs = (1...5).map { loggedAt(daysAgo: $0, hour: 20, minute: 30, type: .dinner) } // +60min
        let proposals = BehaviorObserver.detectPatterns(planned: plannedMeals, logs: logs)

        let drift = proposals.first { proposal in
            if case let .timeDrift(type, delta, dir) = proposal.kind,
               type == "dinner", delta >= 30, dir == .later
            {
                return true
            }
            return false
        }
        #expect(drift != nil)
    }

    @Test func detectsEarlyTimeDrift() {
        let plannedMeals = (1...7).map { planned(name: "Breakfast", daysAgo: $0, time: "08:00") }
        let logs = (1...5).map { loggedAt(daysAgo: $0, hour: 7, minute: 0, type: .breakfast) } // -60min
        let proposals = BehaviorObserver.detectPatterns(planned: plannedMeals, logs: logs)

        let drift = proposals.first { proposal in
            if case let .timeDrift(_, delta, dir) = proposal.kind, delta >= 30, dir == .earlier { return true }
            return false
        }
        #expect(drift != nil)
    }

    @Test func emitsReinforceWhenFiveOrMoreDaysAreWithin15Min() {
        let plannedMeals = (1...7).map { planned(name: "Lunch", daysAgo: $0, time: "13:00") }
        let logs = (1...6).map { loggedAt(daysAgo: $0, hour: 13, minute: 5, type: .lunch) }
        let proposals = BehaviorObserver.detectPatterns(planned: plannedMeals, logs: logs)

        let reinforce = proposals.first { proposal in
            if case let .reinforceOnTime(type, count) = proposal.kind, type == "lunch", count >= 5 { return true }
            return false
        }
        #expect(reinforce != nil)
    }

    @Test func emptyInputsProduceNoProposals() {
        let proposals = BehaviorObserver.detectPatterns(planned: [], logs: [])
        #expect(proposals.isEmpty)
    }
}

@MainActor
struct BehaviorObserverApplyTests {

    @Test func skipProposalInsertsObservedPreference() throws {
        let container = try makeObserverContainer()
        let context = container.mainContext
        let proposal = BehaviorProposal(
            subject: LearnedPreferenceSubject.mealTimingDinner,
            text: "Often skips dinner (skipped 4 of last 7 days)",
            kind: .skip(type: "dinner", count: 4, of: 7)
        )
        BehaviorObserver.apply(proposal: proposal, existing: [], in: context, now: Date())
        try context.save()

        let active = BehaviorObserver.fetchActivePreferences(in: context)
        #expect(active.count == 1)
        #expect(active.first?.subject == LearnedPreferenceSubject.mealTimingDinner)
        #expect(active.first?.source == .observed)
    }

    @Test func reinforceOnTimeWithoutExistingPrefDoesNothing() throws {
        let container = try makeObserverContainer()
        let context = container.mainContext
        let proposal = BehaviorProposal(
            subject: LearnedPreferenceSubject.mealTimingLunch,
            text: "On-time lunch",
            kind: .reinforceOnTime(type: "lunch", count: 6)
        )
        BehaviorObserver.apply(proposal: proposal, existing: [], in: context, now: Date())
        try context.save()
        #expect(BehaviorObserver.fetchActivePreferences(in: context).isEmpty)
    }

    @Test func reinforceOnTimeWithMatchingExistingPrefBumpsEvidence() throws {
        let container = try makeObserverContainer()
        let context = container.mainContext
        let existing = LearnedPreference(
            text: "Eats lunch at 13:00",
            subject: LearnedPreferenceSubject.mealTimingLunch,
            confidence: 0.5,
            source: .observed,
            evidenceCount: 1
        )
        context.insert(existing)
        let proposal = BehaviorProposal(
            subject: LearnedPreferenceSubject.mealTimingLunch,
            text: "On-time lunch",
            kind: .reinforceOnTime(type: "lunch", count: 6)
        )
        BehaviorObserver.apply(proposal: proposal, existing: [existing], in: context, now: Date())
        #expect(existing.evidenceCount == 2)
    }

    @Test func observationDoesNotOverwriteUserVerifiedPreference() throws {
        let container = try makeObserverContainer()
        let context = container.mainContext
        let pinned = LearnedPreference(
            text: "Eats dinner at 19:30",
            subject: LearnedPreferenceSubject.mealTimingDinner,
            confidence: 0.9,
            source: .explicit,
            userVerified: true
        )
        context.insert(pinned)
        let proposal = BehaviorProposal(
            subject: LearnedPreferenceSubject.mealTimingDinner,
            text: "Eats dinner ~60min later than planned (5 of 7 days)",
            kind: .timeDrift(type: "dinner", deltaMinutes: 60, direction: .later)
        )
        BehaviorObserver.apply(proposal: proposal, existing: [pinned], in: context, now: Date())
        // User-stated pref should NOT be reinforced by a contradicting observation.
        #expect(pinned.evidenceCount == 1)
        // And no new pref should be inserted because the text contains "dinner" + "later" so it matched.
        let active = BehaviorObserver.fetchActivePreferences(in: context)
        #expect(active.count == 1)
    }
}
