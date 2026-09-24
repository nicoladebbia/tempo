//
// DailyNutritionTargets.swift
// Tempo
//
// THE canonical daily nutrition target. Every surface that shows "X / Y kcal"
// (Nutrition Today, the same-day rebalancer, and — after the Dashboard swap —
// the Fuel quadrant) must get Y from here so they can never disagree:
//
//   target = adjust( base + carryover )
//
//   base       NutritionTargetCalculator.targetsForToday(todayMeals:…) — the
//              plan's baseline allocation for today, or the TDEE estimate
//              when no plan covers today.
//   carryover  MacroCarryoverService.activeAdjustmentForToday — the capped
//              single-day refund from yesterday's real shortfall.
//   adjust     NutritionEngine.adjustedTargets — recovery zone + training /
//              rest day (rest −15%, red +10% kcal/+15% protein, green+training
//              +20% carbs, yellow+training +10% carbs).
//
// `note` is the short human-readable explanation Nutrition Today shows under
// the calorie bar ("Rest day −15% · +150 kcal from yesterday").
//

import Foundation
import SwiftData

struct DailyNutritionTargets: Equatable {
    /// Final targets after carryover + adjustment. What the UI shows.
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let hydrationMl: Int

    /// Base (plan baseline or TDEE estimate), before carryover and adjustment.
    let base: NutritionTargetCalculator.Targets
    /// Base + carryover — the input the recovery/rest adjustment ran on.
    let beforeAdjustment: NutritionTargetCalculator.Targets
    let mode: NutritionMode
    /// Why today's target differs from the base. nil when it doesn't.
    let note: String?

    var targets: NutritionTargetCalculator.Targets {
        NutritionTargetCalculator.Targets(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    // MARK: - Day context

    /// Today's training status + logged activity. Mirrors the Dashboard's
    /// `refreshTrainingStatus` reading of today's WorkoutPlan.
    struct DayContext: Equatable {
        var isTrainingDay: Bool
        var isRestDay: Bool
        /// Summed calories / minutes of today's logged ActivitySessions
        /// (football etc.) — feeds the sweat-based hydration bonus.
        var activityCaloriesBurned: Double?
        var activityDurationMin: Double?

        /// No workout plan and no logged activity: neither a training day
        /// nor a rest day → no rest cut, no training carb bump.
        static let unknown = DayContext(isTrainingDay: false, isRestDay: false)
    }

    // MARK: - Pure compute

    /// Pure arithmetic over already-fetched inputs. Nutrition Today calls
    /// this with its cached state so the view stays reactive; `today(in:)`
    /// calls it after fetching the same inputs.
    static func compute(
        todayMeals: [PlannedMeal],
        dietaryProfile: DietaryProfile?,
        whoopAvgTDEE: Double?,
        carryover: MacroCarryoverService.DailyAdjustment,
        day: DayContext,
        recoveryScore: Double?,
        strain: Double? = nil
    ) -> DailyNutritionTargets {
        let base = NutritionTargetCalculator.targetsForToday(
            todayMeals: todayMeals,
            dietaryProfile: dietaryProfile,
            whoopAvgTDEE: whoopAvgTDEE
        )
        return compute(base: base, carryover: carryover, day: day, recoveryScore: recoveryScore, strain: strain)
    }

    static func compute(
        base: NutritionTargetCalculator.Targets,
        carryover: MacroCarryoverService.DailyAdjustment,
        day: DayContext,
        recoveryScore: Double?,
        strain: Double? = nil
    ) -> DailyNutritionTargets {
        let withCarryover = NutritionTargetCalculator.applying(carryover, to: base)
        let adjusted = NutritionEngine.adjustedTargets(
            baseCalories: withCarryover.calories,
            baseProtein: withCarryover.protein,
            baseCarbs: withCarryover.carbs,
            baseFat: withCarryover.fat,
            recoveryZone: recoveryScore.map { RecoveryZone(score: $0) },
            currentStrain: strain,
            isTrainingDay: day.isTrainingDay,
            isRestDay: day.isRestDay,
            activityCaloriesBurned: day.activityCaloriesBurned,
            activityDurationMin: day.activityDurationMin
        )
        return DailyNutritionTargets(
            calories: adjusted.calorieTarget,
            protein: adjusted.proteinTarget,
            carbs: adjusted.carbsTarget,
            fat: adjusted.fatTarget,
            hydrationMl: adjusted.hydrationTargetMl,
            base: base,
            beforeAdjustment: withCarryover,
            mode: adjusted.mode,
            note: note(
                mode: adjusted.mode,
                beforeAdjustment: withCarryover,
                adjusted: adjusted,
                carryover: carryover
            )
        )
    }

    // MARK: - Fetching entry point

    /// Full canonical target for today, fetched from `context`. Use this
    /// anywhere that has a ModelContext but no NutritionTabViewModel (the
    /// rebalancer, the Dashboard).
    ///
    /// - Parameters:
    ///   - whoopAvgTDEE: 7-day Whoop expenditure average (`WhoopService.weeklyTDEEAverage`).
    ///     Only affects the no-plan estimate.
    ///   - recoveryScore: today's recovery score 0–100, nil when unknown.
    ///   - strain: today's strain (passed through to NutritionEngine; currently unused there).
    @MainActor
    static func today(
        in context: ModelContext,
        whoopAvgTDEE: Double?,
        recoveryScore: Double?,
        strain: Double? = nil
    ) -> DailyNutritionTargets {
        let profileDescriptor = FetchDescriptor<DietaryProfile>(
            predicate: #Predicate<DietaryProfile> { $0.isActive == true }
        )
        return compute(
            todayMeals: CanonicalMeals.meals(on: Date(), in: context),
            dietaryProfile: (try? context.fetch(profileDescriptor))?.first,
            whoopAvgTDEE: whoopAvgTDEE,
            carryover: MacroCarryoverService.activeAdjustmentForToday(in: context),
            day: dayContext(in: context),
            recoveryScore: recoveryScore,
            strain: strain
        )
    }

    /// Today's training/rest status from the persisted WorkoutPlan (same
    /// survivor rule as the Dashboard: an in-progress session wins, else the
    /// most recent row) plus today's logged ActivitySessions. A logged
    /// activity makes it a training day even without a gym plan. Read-only —
    /// does not run the workout-plan ensurer.
    @MainActor
    static func dayContext(in context: ModelContext, now: Date = Date()) -> DayContext {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return .unknown
        }
        let planDescriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { plan in
                plan.date >= today && plan.date < tomorrow
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let plans = (try? context.fetch(planDescriptor)) ?? []
        let plan = plans.first { $0.status == .inProgress } ?? plans.first

        let activityDescriptor = FetchDescriptor<ActivitySession>(
            predicate: #Predicate<ActivitySession> { $0.date == today }
        )
        let sessions = (try? context.fetch(activityDescriptor)) ?? []
        let activityCal = sessions.compactMap(\.caloriesBurned).reduce(0, +)
        let activityMin = sessions.compactMap(\.durationMinutes).reduce(0, +)

        var isTraining = !sessions.isEmpty
        var isRest = false
        if let plan {
            switch plan.status {
            case .completed,
                 .inProgress:
                isTraining = true
            case .planned:
                if plan.type == .rest {
                    isRest = !isTraining
                } else {
                    isTraining = true
                }
            case .skipped:
                break
            }
        }
        return DayContext(
            isTrainingDay: isTraining,
            isRestDay: isRest,
            activityCaloriesBurned: activityCal > 0 ? activityCal : nil,
            activityDurationMin: activityMin > 0 ? activityMin : nil
        )
    }

    // MARK: - Note

    static func note(
        mode: NutritionMode,
        beforeAdjustment: NutritionTargetCalculator.Targets,
        adjusted: AdjustedNutritionTargets,
        carryover: MacroCarryoverService.DailyAdjustment
    ) -> String? {
        var parts: [String] = []
        switch mode {
        case .rest:
            parts.append("Rest day −15%")
        case .repair:
            parts.append("Red recovery +10% kcal, +15% protein")
        case .fuel:
            parts.append("Green recovery + training +20% carbs")
        case .standard:
            if adjusted.carbsTarget > beforeAdjustment.carbs {
                parts.append("Yellow recovery + training +10% carbs")
            }
        }
        let refund = Int(carryover.calories.rounded())
        if carryover.hasActiveCarryover, refund > 0 {
            parts.append("+\(refund) kcal from yesterday")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
