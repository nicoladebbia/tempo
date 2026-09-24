//
// DashboardViewModel+WidgetSync.swift
// Tempo
//
// Builds the widget snapshot from the Dashboard's quadrants — the same
// numbers the Dashboard shows — and hands it to WidgetSyncService. Called at
// the end of every refresh path (refreshBody, refreshTrainingStatus,
// refreshAccountability), so a logged meal (.tempoNutritionLogged → refresh)
// reaches the widget without opening another screen.
//

import Foundation

extension DashboardViewModel {
    var widgetSnapshot: WidgetSnapshot {
        let nextExam = mind.exams
            .filter { $0.daysUntil >= 0 }
            .min { $0.date < $1.date }
            .map { "\($0.name): \($0.formattedCountdown)" } ?? ""

        return WidgetSnapshot(
            dailyScore: dailyScore ?? 0,
            recoveryZone: (body.recoveryZone ?? .green).rawValue,
            recoveryScore: Int((body.recoveryScore ?? 0).rounded()),
            sleepHours: body.sleepHours ?? 0,
            hrv: body.hrv ?? 0,
            rhr: Int((body.rhr ?? 0).rounded()),
            caloriesConsumed: fuel.caloriesConsumed ?? 0,
            caloriesTarget: fuel.calorieTarget ?? 0,
            protein: fuel.proteinGrams ?? 0,
            carbs: fuel.carbsGrams ?? 0,
            fat: fuel.fatGrams ?? 0,
            mealsLogged: fuel.mealsLogged ?? 0,
            mealsTarget: fuel.mealsPlanned ?? 0,
            studyMinutes: mind.studyMinutesToday,
            studyTargetMinutes: mind.studyTargetMinutes,
            streakCount: mind.currentStreakDays,
            nextExam: nextExam,
            workoutDone: move.workoutStatus == .completed,
            stepCount: move.steps ?? 0,
            activeCalories: move.activeCalories ?? 0,
            nnCompleted: nonNegotiablesDone,
            nnTotal: nonNegotiablesTotal
        )
    }

    func pushWidgetSnapshot() {
        WidgetSyncService.publish(widgetSnapshot)
    }
}
