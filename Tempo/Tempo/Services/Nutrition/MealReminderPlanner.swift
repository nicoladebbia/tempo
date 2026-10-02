//
// MealReminderPlanner.swift
// Tempo
//
// The pre-meal "Fuel Up" reminder: 15 minutes before EVERY planned meal
// (status planned or modified, today and the days ahead of the active plan),
// soonest first, only while Settings -> Meal Reminders is on. Rebuilt whenever
// the plan changes and when the app opens; one meal is re-armed on undo /
// shift. Eating or skipping a meal cancels its reminder (MealOutcomeService).
//

import Foundation
import OSLog
import SwiftData

enum MealReminderPlanner {
    static let leadMinutes = 15

    /// `UserSettings.mealRemindersEnabled`; a fresh install without a settings
    /// row yet gets the default (on).
    static func isEnabled(modelContext: ModelContext) -> Bool {
        (try? modelContext.fetch(FetchDescriptor<UserSettings>()))?.first?.mealRemindersEnabled ?? true
    }

    /// The reminder for one meal, nil when it has already fired or the meal
    /// is no longer waiting to be eaten.
    static func reminder(for meal: PlannedMeal, scheduled: Date, now: Date = Date()) -> MealReminderRequest? {
        guard meal.status == .planned || meal.status == .modified else {
            return nil
        }
        let fire = scheduled.addingTimeInterval(-Double(leadMinutes) * 60)
        guard fire > now else {
            return nil
        }
        return MealReminderRequest(mealID: meal.id, mealName: meal.mealName, fireDate: fire)
    }

    /// Every pending pre-meal reminder the active plan calls for, soonest first.
    static func requests(
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MealReminderRequest]? {
        let startOfToday = calendar.startOfDay(for: now)
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= startOfToday
            }
        )
        // A failed fetch must not read as "no meals" (that would wipe every
        // pending reminder); the caller leaves the current ones alone.
        guard let meals = try? modelContext.fetch(descriptor) else {
            return nil
        }
        // Active-plan filter in Swift: relationship predicates miss
        // not-yet-faulted rows.
        return meals
            .filter { $0.mealPlan?.isActive == true }
            .compactMap { meal in
                reminder(
                    for: meal,
                    scheduled: MealScheduleHelpers.scheduledDate(for: meal, calendar: calendar),
                    now: now
                )
            }
            .sorted { $0.fireDate < $1.fireDate }
    }

    /// Makes the pending pre-meal reminders match the plan. Switched off ->
    /// removes them all.
    static func reschedule(
        modelContext: ModelContext,
        notifications: any NotificationServiceProtocol,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard isEnabled(modelContext: modelContext) else {
            notifications.replaceMealReminders([])
            return
        }
        guard let wanted = requests(modelContext: modelContext, now: now, calendar: calendar) else {
            return
        }
        notifications.replaceMealReminders(wanted)
        Logger.nutrition.info("[MealReminders] \(wanted.count, privacy: .public) scheduled")
        for reminder in wanted.prefix(5) {
            Logger.nutrition.info(
                "[MealReminders] \(reminder.mealName, privacy: .public) \(reminder.mealID.uuidString, privacy: .public) fires \(reminder.fireDate, privacy: .public)"
            )
        }
    }
}
