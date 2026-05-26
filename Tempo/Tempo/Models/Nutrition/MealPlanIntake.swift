//
// MealPlanIntake.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation

// MARK: - MealPlanIntake

struct MealPlanIntake: Sendable, Equatable {
    var cookableDaysThisWeek: Int
    var leftoverTolerance: LeftoverTolerance
    var eatingWindow: EatingWindow
    var groceryIntent: GroceryIntent?
    var recoveryAdjusted: Bool
    var temporaryExclusions: [String]
    /// The user's actual weekly training schedule pulled from UserSettings.
    /// Without this, MealPlanPrompts told the AI to "assign day types to
    /// match a typical training week" — i.e. a generic guess — and the
    /// Plan tab showed Wed=strength / Thu=cardio that bore no relation to
    /// the real Mon=upper, Tue=lower, Wed=football schedule. nil when the
    /// user hasn't completed Training settings yet.
    var trainingSchedule: WeeklyTrainingSchedule?

    static let `default` = MealPlanIntake(
        cookableDaysThisWeek: 4,
        leftoverTolerance: .twoToThreeDayBatches,
        eatingWindow: .default,
        groceryIntent: nil,
        recoveryAdjusted: false,
        temporaryExclusions: [],
        trainingSchedule: nil
    )
}

// MARK: - WeeklyTrainingSchedule

/// User's actual weekly training schedule derived from UserSettings —
/// trainingSplit + footballDays projected onto the 7-day week. Passed to
/// MealPlanGeneratorService so the AI assigns calorie day-types that
/// match what the user actually trains.
struct WeeklyTrainingSchedule: Sendable, Equatable {
    /// Day-of-week (1 = Monday … 7 = Sunday) → human-readable training kind
    /// for that day. Example: 1: "Upper", 2: "Lower", 3: "Football", …
    var byWeekday: [Int: String]

    /// Returns a prompt-ready bulleted list ordered Monday → Sunday.
    var formattedForPrompt: String {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return (1 ... 7).compactMap { weekday in
            guard let kind = byWeekday[weekday] else { return nil }
            return "- \(names[weekday - 1]): \(kind)"
        }.joined(separator: "\n")
    }

    /// Build a 7-day schedule from the user's TrainingSplit + footballDays
    /// settings. Mirrors what TrainingEngine.generateWeekPlan produces for
    /// the Training tab so the Nutrition Plan tab now says the same thing
    /// the Training Week Plan tab says — no more "Wednesday strength" when
    /// the user has Wednesday football. Used by NutritionTabViewModel when
    /// it builds the MealPlanIntake for regeneration.
    static func make(split: TrainingSplit, footballDays: ActiveDays) -> WeeklyTrainingSchedule {
        // Base 6-day split pattern in Mon..Sat slots (Sunday = Rest unless
        // football lands there). These match the canonical split layouts
        // shipped with the Training engine.
        let base: [String]
        switch split {
        case .pushPullLegs:
            // Mon Push, Tue Pull, Wed Legs, Thu Push, Fri Pull, Sat Legs
            base = ["Push", "Pull", "Legs", "Push", "Pull", "Legs"]
        case .upperLower:
            // Mon Upper, Tue Lower, Wed Upper, Thu Lower, Fri Upper, Sat Lower
            base = ["Upper", "Lower", "Upper", "Lower", "Upper", "Lower"]
        case .fullBody:
            // Mon, Wed, Fri Full Body; Tue/Thu/Sat Mobility
            base = ["Full Body", "Mobility", "Full Body", "Mobility", "Full Body", "Mobility"]
        case .bro:
            // Mon Chest, Tue Back, Wed Legs, Thu Shoulders, Fri Arms, Sat Mobility
            base = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Mobility"]
        case .custom:
            // No assumption — let the AI fall back to its own heuristic.
            base = ["Strength", "Strength", "Strength", "Strength", "Strength", "Mobility"]
        }
        var byWeekday: [Int: String] = [:]
        for (i, label) in base.enumerated() {
            byWeekday[i + 1] = label
        }
        byWeekday[7] = "Rest"
        // Overlay football days. Football overrides the base split on that day
        // — that's how the Training engine treats it (football is the priority
        // signal). Without this, a user with Mon=upper and Wed=football would
        // still see Wed=Legs in the meal plan.
        //
        // Coordinate note: `byWeekday` is keyed Mon-1…Sun-7 (this file's own
        // convention). `ActiveDays.isActive(on:)` expects Calendar-standard
        // weekday (1=Sun, 2=Mon, …, 7=Sat). Convert Mon-1 → Calendar-standard
        // via `(weekday % 7) + 1`: Mon(1)→2, Tue(2)→3, …, Sat(6)→7, Sun(7)→1.
        // Previously this passed the Mon-1 index raw and shifted every
        // football day one slot earlier in the nutrition weekly schedule.
        for weekday in 1 ... 7 where footballDays.isActive(on: (weekday % 7) + 1) {
            byWeekday[weekday] = "Football"
        }
        return WeeklyTrainingSchedule(byWeekday: byWeekday)
    }
}

// MARK: - LeftoverTolerance

enum LeftoverTolerance: String, Sendable, CaseIterable, Identifiable {
    case freshDaily
    case twoToThreeDayBatches
    case fullWeekPrep

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .freshDaily: "Fresh every day"
        case .twoToThreeDayBatches: "2-3 day batches"
        case .fullWeekPrep: "Full-week prep"
        }
    }

    var promptDescriptor: String {
        switch self {
        case .freshDaily: "User wants fresh meals every day. No repeating the same recipe back-to-back."
        case .twoToThreeDayBatches: "User accepts the same meal across 2-3 consecutive days. Batch cooking is welcome."
        case .fullWeekPrep: "User prefers Sunday-style meal prep. Many meals can repeat across the week."
        }
    }
}

// MARK: - EatingWindow

struct EatingWindow: Sendable, Equatable {
    var firstMealHour: Int
    var lastMealHour: Int

    static let `default` = EatingWindow(firstMealHour: 8, lastMealHour: 20)

    var isValid: Bool {
        firstMealHour >= 0 && firstMealHour < 24
            && lastMealHour > firstMealHour && lastMealHour < 24
    }

    var formattedForPrompt: String {
        let firstFormatted = String(format: "%02d:00", firstMealHour)
        let lastFormatted = String(format: "%02d:00", lastMealHour)
        return "First meal anchored at \(firstFormatted). Last meal anchored at \(lastFormatted)."
    }
}

// MARK: - GroceryIntent

struct GroceryIntent: Sendable, Equatable {
    var willShopThisWeek: Bool
    var budgetCapUSD: Int?
    var preferredStores: [String]

    var formattedForPrompt: String {
        var parts: [String] = []
        parts.append(willShopThisWeek
            ? "User is doing a grocery run this week — fresh purchases allowed."
            : "User is NOT shopping this week — meals must work from current pantry + minimal additions.")
        if let cap = budgetCapUSD {
            parts.append("Budget cap for the week: $\(cap).")
        }
        if !preferredStores.isEmpty {
            parts.append("Preferred stores: \(preferredStores.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }
}
