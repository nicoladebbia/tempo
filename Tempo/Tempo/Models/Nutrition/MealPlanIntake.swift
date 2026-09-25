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
    /// From onboarding (`UserDailyPlanProfile.breakfastSkipped`): the planner
    /// must not program a breakfast slot. Not editable in the wizard.
    var breakfastSkipped: Bool = false
    /// From onboarding (`UserDailyPlanProfile.postWorkoutMandatory`): every
    /// training day gets a dedicated post-training refuel meal.
    var postWorkoutMandatory: Bool = false

    static let `default` = MealPlanIntake(
        cookableDaysThisWeek: 4,
        leftoverTolerance: .twoToThreeDayBatches,
        eatingWindow: .default,
        groceryIntent: nil,
        recoveryAdjusted: false,
        temporaryExclusions: [],
        trainingSchedule: nil
    )

    // MARK: - Onboarding seed (UserDailyPlanProfile → MealPlanIntake)

    /// True once the wizard or AI Meals settings has saved an eating window.
    /// Until then the onboarding window is the user's only real answer.
    static func hasPersistedEatingWindow(_ settings: UserSettings?) -> Bool {
        settings?.mealIntakeFirstMealHour != nil || settings?.mealIntakeLastMealHour != nil
    }

    /// Hour-granularity window from onboarding's minute-precision one. The
    /// start rounds UP and the end rounds DOWN so meals always land inside
    /// the window (11:30–19:45 → 12–19). nil when the result is unusable.
    static func eatingWindow(fromOnboarding dailyPlan: UserDailyPlanProfile) -> EatingWindow? {
        let start = dailyPlan.eatingWindowStartMinutes
        let end = dailyPlan.eatingWindowEndMinutes
        guard start >= 0, end > start, end <= 24 * 60 else { return nil }
        let window = EatingWindow(
            firstMealHour: Int((Double(start) / 60).rounded(.up)),
            lastMealHour: min(23, end / 60)
        )
        return window.isValid ? window : nil
    }

    /// Fold the onboarding eating preferences into an intake:
    ///  - eating window → only when the wizard / AI Meals settings never saved
    ///    one (those are explicit overrides and win);
    ///  - breakfastSkipped / postWorkoutMandatory → always (onboarding is
    ///    their only source).
    /// Used to pre-fill the wizard and, in the generator, for every plan.
    func applyingOnboarding(_ dailyPlan: UserDailyPlanProfile?, settings: UserSettings?) -> MealPlanIntake {
        guard let dailyPlan else { return self }
        var copy = self
        if !Self.hasPersistedEatingWindow(settings), let window = Self.eatingWindow(fromOnboarding: dailyPlan) {
            copy.eatingWindow = window
        }
        copy.breakfastSkipped = dailyPlan.breakfastSkipped
        copy.postWorkoutMandatory = dailyPlan.postWorkoutMandatory
        return copy
    }

    /// Wizard pre-fill: persisted prefs (or defaults) + onboarding eating window.
    static func seeded(settings: UserSettings?, dailyPlan: UserDailyPlanProfile?) -> MealPlanIntake {
        let base = settings.map { loadPersisted(from: $0) } ?? .default
        return base.applyingOnboarding(dailyPlan, settings: settings)
    }

    // MARK: - Persistence (UserSettings ↔ MealPlanIntake)

    /// Build an intake from the user's PERSISTED preferences on `UserSettings`,
    /// falling back to `.default` per-field when a value was never set (nil).
    /// This is what every non-wizard generate path now uses instead of bare
    /// `.default`, so "Regenerate Plan" respects the user's real cooking prefs.
    /// `trainingSchedule` and `groceryIntent` are NOT set here — the view model
    /// enriches those from UserSettings (training split + football days, grocery
    /// budget + stores) on each generate, as it already did.
    static func loadPersisted(from settings: UserSettings) -> MealPlanIntake {
        let window = EatingWindow(
            firstMealHour: settings.mealIntakeFirstMealHour ?? EatingWindow.default.firstMealHour,
            lastMealHour: settings.mealIntakeLastMealHour ?? EatingWindow.default.lastMealHour
        )
        let leftover = settings.mealIntakeLeftoverToleranceRaw
            .flatMap { LeftoverTolerance(rawValue: $0) } ?? MealPlanIntake.default.leftoverTolerance
        let exclusions = settings.mealIntakeExclusionsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return MealPlanIntake(
            cookableDaysThisWeek: settings.mealIntakeCookableDays ?? MealPlanIntake.default.cookableDaysThisWeek,
            leftoverTolerance: leftover,
            eatingWindow: window.isValid ? window : .default,
            groceryIntent: nil,
            recoveryAdjusted: settings.mealIntakeRecoveryAdjusted,
            temporaryExclusions: exclusions,
            trainingSchedule: nil
        )
    }

    /// Write this intake's persistable fields back to `UserSettings` so the
    /// next regenerate reuses them. Called by the wizard's onComplete (and the
    /// future AI Meals settings page). Grocery + training are persisted/derived
    /// elsewhere, so they're not touched here.
    func persist(to settings: UserSettings) {
        settings.mealIntakeCookableDays = cookableDaysThisWeek
        settings.mealIntakeLeftoverToleranceRaw = leftoverTolerance.rawValue
        settings.mealIntakeFirstMealHour = eatingWindow.firstMealHour
        settings.mealIntakeLastMealHour = eatingWindow.lastMealHour
        settings.mealIntakeRecoveryAdjusted = recoveryAdjusted
        settings.mealIntakeExclusionsRaw = temporaryExclusions.joined(separator: ", ")
        settings.updatedAt = Date()
    }
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
            guard let kind = byWeekday[weekday] else {
                return nil
            }
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
        let base: [String] = switch split {
        case .pushPullLegs:
            // Mon Push, Tue Pull, Wed Legs, Thu Push, Fri Pull, Sat Legs
            ["Push", "Pull", "Legs", "Push", "Pull", "Legs"]
        case .upperLower:
            // Mon Upper, Tue Lower, Wed Upper, Thu Lower, Fri Upper, Sat Lower
            ["Upper", "Lower", "Upper", "Lower", "Upper", "Lower"]
        case .fullBody:
            // Mon, Wed, Fri Full Body; Tue/Thu/Sat Mobility
            ["Full Body", "Mobility", "Full Body", "Mobility", "Full Body", "Mobility"]
        case .bro:
            // Mon Chest, Tue Back, Wed Legs, Thu Shoulders, Fri Arms, Sat Mobility
            ["Chest", "Back", "Legs", "Shoulders", "Arms", "Mobility"]
        case .custom:
            // No assumption — let the AI fall back to its own heuristic.
            ["Strength", "Strength", "Strength", "Strength", "Strength", "Mobility"]
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
        // `weekday` here is THIS struct's convention (Mon=1 … Sun=7), but
        // `ActiveDays.isActive(on:)` expects Calendar's convention (Sun=1 …
        // Sat=7). Convert ONLY the argument — Mon(1)→2, …, Sat(6)→7, Sun(7)→1.
        // The dict key stays in Mon=1…Sun=7. Without this, a user with Sunday
        // football got Monday=Football in the meal plan (bit 6 = Sunday read as
        // Calendar-Monday). Measured via [PlanDiag] wd1=Football.
        for weekday in 1 ... 7 where footballDays.isActive(on: (weekday % 7) + 1) {
            byWeekday[weekday] = "Football"
        }
        return WeeklyTrainingSchedule(byWeekday: byWeekday)
    }

    /// Build the schedule from `TrainingScheduleProvider`'s week — the real
    /// generation path (split, custom weekday map, recovery, matches,
    /// emphasis, deload, and the active TrainerProgram overlay) instead of
    /// the settings-only guess `make(split:footballDays:)` produced. This is
    /// what every generate path now uses; `make` stays only for its existing
    /// unit tests.
    /// A second same-day session (two-a-day) is appended as "Main + Second"
    /// so the AI's existing "two trainings in one day → double" rule (see
    /// MealPlanPrompts) actually has something to key off.
    static func build(from week: [DayTrainingSchedule]) -> WeeklyTrainingSchedule {
        var byWeekday: [Int: String] = [:]
        for day in week {
            var label = day.mainType.displayName
            if let secondary = day.secondaryType {
                label += " + \(secondary.displayName)"
            }
            byWeekday[day.weekday] = label
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

    /// Clamp an "HH:mm" time into the window (inclusive). Malformed input is
    /// returned unchanged.
    func clamp(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else {
            return hhmm
        }
        let minutes = min(max(h * 60 + m, firstMealHour * 60), lastMealHour * 60)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    var formattedForPrompt: String {
        let firstFormatted = String(format: "%02d:00", firstMealHour)
        let lastFormatted = String(format: "%02d:00", lastMealHour)
        // OUTER BOUNDS, not the meal target. The actual meal times come from
        // <observed_meal_times> (anchored to the user's real wake). This window
        // only constrains: no meal scheduled before firstFormatted or after
        // lastFormatted. Phrasing it as "anchored at 08:00" previously made the
        // AI pin breakfast to 08:00, fighting the wake-derived time.
        return "Eating window bounds: schedule no meal before \(firstFormatted) "
            + "or after \(lastFormatted). These bounds OVERRIDE the default "
            + "per-meal time windows. Within them, use the observed_meal_times exactly."
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
