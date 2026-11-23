//
// TodaySnapshot+Live.swift
// Tempo
//
// Builds the Today snapshot from the live view model and the stores each tab
// owns, so a number on Today is the same number its own tab shows.
//

import Foundation
import SwiftData

extension TodaySnapshot {
    /// Values Today reads from the tab that owns them rather than from the
    /// Dashboard view model.
    struct Owned: Equatable {
        /// The Fuel tab's water target (same call its water card makes).
        var waterTargetMl: Int?
        /// Today's saved recovery row: what the Recovery page shows.
        var recoveryScore: Double?
        var sleepHours: Double?
        var hrv: Double?
        var restingHR: Double?

        @MainActor
        static func read(in context: ModelContext, now: Date = Date()) -> Owned {
            let start = Calendar.current.startOfDay(for: now)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? now
            let row = (try? context.fetch(FetchDescriptor<DailyRecovery>(
                predicate: #Predicate { $0.date >= start && $0.date < end }
            )))?.first
            let water = DailyNutritionTargets.today(
                in: context,
                whoopAvgTDEE: nil,
                recoveryScore: DailyNutritionTargets.storedRecoveryScore(in: context, now: now)
            ).hydrationMl
            return Owned(
                waterTargetMl: water,
                recoveryScore: row?.recoveryScore,
                sleepHours: row?.sleepHours,
                hrv: row?.hrvRmssd,
                restingHR: row?.restingHR
            )
        }
    }

    @MainActor
    static func live(
        vm: DashboardViewModel,
        firstName: String?,
        owned: Owned,
        whoopConnected: Bool,
        healthAuthorized: Bool,
        now: Date = Date()
    ) -> TodaySnapshot {
        let body = vm.body, fuel = vm.fuel, mind = vm.mind, move = vm.move

        return TodaySnapshot(
            day: Calendar.current.startOfDay(for: now),
            firstName: firstName,
            score: vm.dailyScore,
            workout: Workout(
                status: workoutStatus(move.workoutStatus),
                name: move.workoutName,
                inProgress: move.workoutInProgress,
                durationMinutes: move.workoutDurationMinutes
            ),
            recovery: recovery(body: body, owned: owned, whoopConnected: whoopConnected),
            fuel: Fuel(
                calories: fuel.caloriesConsumed,
                calorieTarget: fuel.calorieTarget,
                protein: fuel.proteinGrams,
                proteinTarget: fuel.proteinTarget,
                carbs: fuel.carbsGrams,
                carbsTarget: fuel.carbsTarget,
                fat: fuel.fatGrams,
                fatTarget: fuel.fatTarget,
                waterMl: fuel.hydrationMl,
                waterTargetMl: owned.waterTargetMl ?? fuel.hydrationTargetMl
            ),
            tasks: vm.nonNegotiables.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map { TaskItem(id: $0.id, title: $0.title, done: $0.isCompleted) },
            study: Study(
                minutes: mind.studyMinutesToday,
                targetMinutes: mind.studyTargetMinutes,
                nextExam: mind.exams.filter { $0.daysUntil >= 0 }.min { $0.date < $1.date }
                    .map { "\($0.name) \($0.formattedCountdown.lowercased())" }
            ),
            streakDays: mind.currentStreakDays,
            steps: move.steps,
            stepsTarget: move.stepsTarget,
            moveConnected: move.isConnected || healthAuthorized,
            nextMeal: fuel.nextMeal.map { meal in
                Meal(
                    id: meal.id,
                    name: meal.mealName,
                    time: meal.scheduledTime,
                    calories: Int(meal.totalCalories.rounded()),
                    protein: Int(meal.totalProtein.rounded()),
                    imminent: MealScheduleHelpers.isImminent(meal: meal, now: now)
                )
            }
        )
    }

    /// A score of 0 means "no reading", never "0% recovered".
    static func recovery(body: BodyQuadrantData, owned: Owned, whoopConnected: Bool) -> Recovery {
        let score = [body.recoveryScore, owned.recoveryScore]
            .compactMap(\.self)
            .first { $0 > 0 }
            .map { Int($0.rounded()) }
        func whole(_ value: Double?) -> Int? {
            value.flatMap { $0 > 0 ? Int($0.rounded()) : nil }
        }
        let sleep = [body.sleepHours, owned.sleepHours].compactMap(\.self).first { $0 > 0 }
        return Recovery(
            score: score,
            sleepHours: sleep,
            sleepPerformance: whole(body.sleepPerformance),
            hrv: whole(body.hrv ?? owned.hrv),
            restingHR: whole(body.rhr ?? owned.restingHR),
            hasSource: body.isConnected || whoopConnected || score != nil || sleep != nil
        )
    }

    static func workoutStatus(_ status: DashboardWorkoutStatus) -> Workout.Status {
        switch status {
        case .completed: .completed
        case .planned: .planned
        case .restDay: .rest
        case .none: .none
        }
    }
}
