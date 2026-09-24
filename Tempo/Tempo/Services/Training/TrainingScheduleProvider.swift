//
// TrainingScheduleProvider.swift
// Tempo
//
// Single source of truth for "what training happens on each day this week" —
// consumed by every surface OUTSIDE the Training tab that needs to know the
// real week (Nutrition's meal plan, and anything downstream of it). Before
// this existed, Nutrition rebuilt its own guess from raw settings
// (`WeeklyTrainingSchedule.make(split:footballDays:)`), which agreed with
// Training only for the simplest case (a fixed split + recurring football
// days) and silently diverged the moment a trainer program, dated match,
// custom weekday map, or recovery-driven swap was in play — the Nutrition
// tab would target calories/carbs for a day type Training wasn't actually
// running.
//
// `weekSchedule` reuses TrainingViewModel's OWN generation path
// (`weekPlanSnapshot` → `assembleWeekPlans`, the exact function `loadWeekPlan`
// calls) via a throwaway TrainingViewModel instance — the same "stateless
// w.r.t. session state" pattern `DailyResetCoordinator.workoutPlanEnsurer`
// already uses in TempoApp.swift. This guarantees the TrainerProgram overlay
// (TrainingViewModel+TrainerProgram.swift), matches, deload, emphasis and the
// persisted-row substitution for today are ALL included — nothing here
// duplicates a generation rule.
//

import Foundation
import SwiftData

// MARK: - DayTrainingSchedule

/// One day's resolved training, exactly as the Training tab's Week Plan would
/// show it: the main session type, an optional second (two-a-day) session,
/// and whether the day is driven by an active TrainerProgram.
struct DayTrainingSchedule: Sendable, Equatable {
    /// Day-of-week in `WeeklyTrainingSchedule`'s convention: 1 = Monday … 7 = Sunday.
    let weekday: Int
    let date: Date
    let mainType: WorkoutType
    let secondaryType: WorkoutType?
    let isTrainerSession: Bool
}

// MARK: - TrainingScheduleProvider

@MainActor
enum TrainingScheduleProvider {
    /// The real ISO week (Monday…Sunday) containing `date`, in
    /// `DayTrainingSchedule` form. Builds a throwaway `TrainingViewModel` from
    /// the caller's own service instances (so it reads the SAME deterministic
    /// engine / Whoop / HealthKit the live Training tab uses — no mock
    /// substitution in production) and calls `weekPlanSnapshot`, which is
    /// non-mutating and never populates exercises: cheap enough to call from
    /// any screen's regenerate path.
    static func weekSchedule(
        containing date: Date,
        trainingEngine: any TrainingEngineProtocol,
        whoop: any WhoopServiceProtocol,
        healthKit: any HealthKitServiceProtocol,
        modelContext: ModelContext
    ) -> [DayTrainingSchedule] {
        let vm = TrainingViewModel(trainingEngine: trainingEngine, whoop: whoop, healthKit: healthKit)
        let plans = vm.weekPlanSnapshot(containing: date, modelContext: modelContext)
        let cal = Calendar.current
        return plans.map { plan in
            let calWeekday = cal.component(.weekday, from: plan.date) // Calendar: 1 = Sunday … 7 = Saturday
            // Convert to Mon=1…Sun=7 (WeeklyTrainingSchedule's convention).
            let weekday = calWeekday == 1 ? 7 : calWeekday - 1
            return DayTrainingSchedule(
                weekday: weekday,
                date: plan.date,
                mainType: plan.type,
                secondaryType: plan.secondarySessionType,
                isTrainerSession: plan.programSessionKey != nil
            )
        }
    }
}
