//
// DashboardViewModel+DayType.swift
// Tempo
//
// Today's WorkoutPlan → Move status, and the Fuel targets. `refreshBody()`
// used to hardcode `isTrainingDay: true, isRestDay: false` and relied on a
// follow-up `refreshTrainingStatus` call to fix it. Both paths now call
// `canonicalFuelTargets`, which resolves training / rest day itself via
// DailyNutritionTargets — the same function Nutrition Today uses.
//

import Foundation
import SwiftData

// MARK: - DashboardViewModel day type

extension DashboardViewModel {
    /// Dashboard display status for a persisted WorkoutPlan. Single mapping
    /// used by the Move quadrant.
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

    /// Today's Fuel targets — THE canonical daily target
    /// (`DailyNutritionTargets.today`: base + carryover + recovery / rest-day
    /// adjustment over the same meals, day context and weight Nutrition Today
    /// uses), so the Fuel quadrant and Nutrition Today can never disagree.
    /// Recovery / strain come from the Body quadrant (preserved across an
    /// all-cancelled Whoop refresh). Nil context (previews) → defaults.
    func canonicalFuelTargets(in context: ModelContext?) -> DailyNutritionTargets {
        let recoveryScore = body.recoveryScore
        guard let context else {
            return DailyNutritionTargets.compute(
                base: NutritionTargetCalculator.Targets(calories: 2400, protein: 180, carbs: 280, fat: 80),
                carryover: .zero,
                day: .unknown,
                recoveryScore: recoveryScore,
                strain: body.strain
            )
        }
        return DailyNutritionTargets.today(
            in: context,
            whoopAvgTDEE: whoop.weeklyTDEEAverage,
            recoveryScore: recoveryScore,
            strain: body.strain
        )
    }
}
