//
// NutritionTargetCalculator.swift
// Tempo
//
// Shared today-target logic used by BOTH the Nutrition tab and the
// Dashboard's Fuel quadrant. Without this, each surface computed targets
// independently — Dashboard read NutritionTarget (a SwiftData record that
// stores onboarding-time defaults like 2,400), Nutrition Today summed
// today's PlannedMeal.totalCalories from the active plan (3,536). Same
// user, same day, two different numbers. This calculator is the single
// source of truth they both call.
//

import Foundation
import SwiftData

enum NutritionTargetCalculator {
    /// Per-macro target snapshot for today. Used by every surface that
    /// renders "X / Y kcal" so the Y value is identical across views.
    struct Targets: Equatable {
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
    }

    /// Compute today's BASE macro targets (before carryover and the
    /// recovery/rest-day adjustment — `DailyNutritionTargets` layers those on).
    /// PRIMARY branch: when today's meals carry a plan baseline, the target
    /// IS the sum of those baselines — the AI generator's per-day allocation
    /// is the source of truth. Baselines (not live totals) so the target
    /// doesn't move when the user logs a bigger meal or the rebalancer bumps
    /// the remaining ones, and ad-hoc logs (baseline 0) never inflate it.
    /// FALLBACK branch: no plan for today, so we estimate from the
    /// DietaryProfile via TDEECalculator.
    ///
    /// Pass `todayMeals` already filtered to today's date range. The caller
    /// owns the query; this helper just does arithmetic so it stays
    /// trivially callable from any ViewModel.
    static func targetsForToday(
        todayMeals: [PlannedMeal],
        dietaryProfile: DietaryProfile?,
        whoopAvgTDEE: Double? = nil
    ) -> Targets {
        let baseline = todayMeals.reduce(MealMacros.zero) { $0 + $1.planBaseline }
        if baseline.calories > 0 {
            return Targets(
                calories: Int(baseline.calories),
                protein: Int(baseline.protein),
                carbs: Int(baseline.carbs),
                fat: Int(baseline.fat)
            )
        }
        return fallbackTargets(profile: dietaryProfile, whoopAvgTDEE: whoopAvgTDEE)
    }

    /// The data-driven estimate shown when no plan covers today. Routes
    /// through `TDEECalculator` (Mifflin-St Jeor + Katch-McArdle when body fat
    /// is known, blended with a 7-day Whoop expenditure average when supplied)
    /// so the no-plan number is the same precise estimate the plan generator
    /// would start from — NOT a crude hand-rolled Mifflin guess.
    ///
    /// `whoopAvgTDEE` MUST be a multi-day rolling average, never a single
    /// day's burn: the TDEECalculator blend weights Whoop at 60%, so one rest
    /// day would otherwise drag the estimate hundreds of kcal low. Pass nil
    /// when no Whoop window is available — the calculator falls back to the
    /// Mifflin/Katch baseline cleanly.
    ///
    /// Hard fallback (no DietaryProfile at all — fresh install before
    /// onboarding) stays a fixed 2,400 / 180 / 270 / 67.
    private static func fallbackTargets(
        profile: DietaryProfile?,
        whoopAvgTDEE: Double? = nil
    ) -> Targets {
        guard let profile else {
            return Targets(calories: 2400, protein: 180, carbs: 270, fat: 67)
        }
        let result = TDEECalculator.calculate(
            weightKg: profile.currentWeightKg,
            heightCm: profile.heightCm,
            age: profile.age,
            biologicalSex: profile.biologicalSex,
            bodyFatPercent: profile.bodyFatPercent,
            trainingFrequency: profile.trainingFrequency,
            whoopAverageTDEE: whoopAvgTDEE,
            goal: profile.primaryGoal,
            goalWeightKg: profile.goalWeightKg,
            weeklyRateKg: profile.weeklyRateKg
        )
        let macros = result.macroTargets
        return Targets(
            calories: result.adjustedCalories,
            protein: macros.proteinGrams,
            carbs: macros.carbsGrams,
            fat: macros.fatGrams
        )
    }

    /// Fetch today's canonical PlannedMeals and DietaryProfile from a
    /// ModelContext, then compute base + carryover. The recovery/rest-day
    /// adjustment is NOT applied here — `DailyNutritionTargets.today(in:)` is
    /// the full canonical daily target and calls this for its first half.
    @MainActor
    static func targetsForToday(
        in context: ModelContext,
        whoopAvgTDEE: Double? = nil
    ) -> Targets {
        // Same meals Nutrition Today shows: today's canonical PlannedMeals
        // (active plan or unbound manual logs).
        let filtered = CanonicalMeals.meals(on: Date(), in: context)

        let profileDescriptor = FetchDescriptor<DietaryProfile>(
            predicate: #Predicate<DietaryProfile> { p in p.isActive == true }
        )
        let profile = (try? context.fetch(profileDescriptor))?.first

        // whoopAvgTDEE flows into the no-plan TDEE estimate so the Dashboard
        // Fuel surface and Nutrition Today (which passes the same shared
        // WhoopService value) show an identical no-plan number. Ignored when
        // today has plan meals — those ARE the target.
        let base = targetsForToday(
            todayMeals: filtered,
            dietaryProfile: profile,
            whoopAvgTDEE: whoopAvgTDEE
        )
        // Layer in the single-day macro refund (MacroCarryoverService §4).
        // Zero when nothing is in flight.
        return applying(MacroCarryoverService.activeAdjustmentForToday(in: context), to: base)
    }

    /// `base` plus an active carryover refund. Identity when no refund is
    /// in flight. Shared by `targetsForToday(in:)` and `DailyNutritionTargets`
    /// so the refund is added the same way everywhere.
    static func applying(
        _ carryover: MacroCarryoverService.DailyAdjustment,
        to base: Targets
    ) -> Targets {
        guard carryover.hasActiveCarryover else {
            return base
        }
        return Targets(
            calories: max(0, base.calories + Int(carryover.calories.rounded())),
            protein: max(0, base.protein + Int(carryover.protein.rounded())),
            carbs: max(0, base.carbs + Int(carryover.carbs.rounded())),
            fat: max(0, base.fat + Int(carryover.fat.rounded()))
        )
    }
}
