//
// DashboardViewModel+DayType.swift
// Tempo
//
// Resolves "is today a training day / rest day?" for the Fuel targets from
// today's WorkoutPlan, so EVERY refresh path computes the right recovery /
// rest-day adjustment. `refreshBody()` used to hardcode
// `isTrainingDay: true, isRestDay: false` and relied on a follow-up
// `refreshTrainingStatus` call to fix it — a refresh without that call (e.g.
// the .tempoNutritionLogged handler) left a rest day showing a training-day
// target. Both paths now share `dayFlags` + `fuelTargets`.
//

import Foundation
import SwiftData

// MARK: - FuelDayFlags

struct FuelDayFlags: Equatable {
    let isTrainingDay: Bool
    let isRestDay: Bool
}

// MARK: - DashboardViewModel day type

extension DashboardViewModel {
    /// Dashboard display status for a persisted WorkoutPlan. Single mapping
    /// used by both the Move quadrant and the Fuel day flags.
    static func dashboardWorkoutStatus(for plan: WorkoutPlan) -> DashboardWorkoutStatus {
        switch plan.status {
        case .completed:
            .completed
        case .inProgress:
            .planned
        case .planned:
            plan.type == .rest ? .restDay : .planned
        case .skipped:
            .none
        }
    }

    /// Training / rest flags for NutritionEngine.adjustedTargets.
    /// - A planned / in-progress / completed session → training day.
    /// - A planned rest session → rest day (−15% kcal/carbs).
    /// - Skipped or no plan → a HealthKit-logged workout still counts as
    ///   training; otherwise standard targets (neither flag).
    static func dayFlags(planStatus: DashboardWorkoutStatus?, hasLoggedWorkout: Bool) -> FuelDayFlags {
        switch planStatus {
        case .planned,
             .completed:
            FuelDayFlags(isTrainingDay: true, isRestDay: false)
        case .restDay:
            FuelDayFlags(isTrainingDay: false, isRestDay: true)
        case .some(.none),
             nil:
            FuelDayFlags(isTrainingDay: hasLoggedWorkout, isRestDay: false)
        }
    }

    /// Today's WorkoutPlan, picking the same survivor the workout ensurer
    /// keeps: an in-progress session wins, else the most recent.
    static func todayWorkoutPlan(in context: ModelContext, now: Date = Date()) -> WorkoutPlan? {
        let today = Calendar.current.startOfDay(for: now)
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
            return nil
        }
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { plan in
                plan.date >= today && plan.date < tomorrow
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let plans = (try? context.fetch(descriptor)) ?? []
        return plans.first(where: { $0.status == .inProgress }) ?? plans.first
    }

    /// Today's logged non-gym activity (football etc.), summed across
    /// sessions. Feeds the sweat-based hydration bonus. Nil when nothing logged.
    static func todayActivityTotals(
        in context: ModelContext,
        now: Date = Date()
    ) -> (calories: Double?, minutes: Double?) {
        let todayStart = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: #Predicate<ActivitySession> { $0.date == todayStart }
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        let calories = sessions.compactMap(\.caloriesBurned).reduce(0, +)
        let minutes = sessions.compactMap(\.durationMinutes).reduce(0, +)
        return (calories > 0 ? calories : nil, minutes > 0 ? minutes : nil)
    }

    /// Resolve today's flags from SwiftData (nil context → HealthKit only).
    static func resolveDayFlags(in context: ModelContext?, hasLoggedWorkout: Bool) -> FuelDayFlags {
        let status = context
            .flatMap { todayWorkoutPlan(in: $0) }
            .map { dashboardWorkoutStatus(for: $0) }
        return dayFlags(planStatus: status, hasLoggedWorkout: hasLoggedWorkout)
    }

    /// The single Dashboard entry point to NutritionEngine.adjustedTargets —
    /// refreshBody and refreshTrainingStatus both call this so they can't
    /// disagree. (The main session later swaps the base to T1's canonical
    /// daily-target function; the adjustment stays here.)
    static func fuelTargets(
        baseCalories: Int,
        baseProtein: Int,
        baseCarbs: Int,
        baseFat: Int,
        recoveryZone: RecoveryZone?,
        strain: Double?,
        flags: FuelDayFlags,
        activity: (calories: Double?, minutes: Double?)
    ) -> AdjustedNutritionTargets {
        NutritionEngine.adjustedTargets(
            baseCalories: baseCalories,
            baseProtein: baseProtein,
            baseCarbs: baseCarbs,
            baseFat: baseFat,
            recoveryZone: recoveryZone,
            currentStrain: strain,
            isTrainingDay: flags.isTrainingDay,
            isRestDay: flags.isRestDay,
            activityCaloriesBurned: activity.calories,
            activityDurationMin: activity.minutes
        )
    }
}
