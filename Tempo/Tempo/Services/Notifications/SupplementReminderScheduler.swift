//
// SupplementReminderScheduler.swift
// Tempo
//
// Turns `SupplementScheduleEngine`'s output into local notifications: one
// reminder per clock-minute GROUP ("Breakfast: Creatine + Vitamin D3"), for
// today and tomorrow, plus a once-per-restock-cycle "running low" alert
// (`SupplementReorderService`). Always a full cancel + rebuild — the same
// pattern `TrainerSessionReminderScheduler` uses — so a shelf edit, an
// override change, a plan regeneration or a taken toggle can't leave a stale
// reminder behind.
//
// Callers: ContentView, on app foreground and on `.tempoSupplementsChanged` /
// `.tempoWeeklyPlanApplied` (debounced) — see ContentView.swift.
//

import Foundation
import SwiftData

// MARK: - Notification.Name

extension Notification.Name {
    /// Posted whenever the supplement shelf, a per-supplement override, or a
    /// "taken" toggle changes — anything that can move today's doses.
    /// `SupplementReminderScheduler` listens (via ContentView) and rebuilds.
    static let tempoSupplementsChanged = Notification.Name("tempoSupplementsChanged")
}

// MARK: - SupplementDayContext + build

extension SupplementDayContext {
    /// Assembles a day's context from SwiftData: the active plan's decisions
    /// (when one covers `date`), today's planned meals, and training/wake/bed
    /// from the routine — falling back to the trainer/training-time
    /// preference, then a fixed default, so this works with no plan and no
    /// routine at all.
    @MainActor
    static func build(date: Date, modelContext: ModelContext) -> SupplementDayContext {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let weekday = SupplementScheduleEngine.mondayFirstWeekday(for: date, calendar: calendar)

        // Active plan covering this date → its decisions + day type.
        let planDescriptor = FetchDescriptor<WeeklyMealPlan>(
            predicate: #Predicate<WeeklyMealPlan> { $0.isActive == true }
        )
        let plan = ((try? modelContext.fetch(planDescriptor)) ?? []).first { $0.coversDate(dayStart) }
        let planDecisionsByName = Dictionary(
            uniqueKeysWithValues: (plan?.supplementDecisions[weekday] ?? []).map { ($0.name, $0) }
        )
        let planIsTrainingDay = plan?.dayTypes[weekday].map { $0 != .rest }

        // Routine: wake/bed + today's training slot.
        let profile = UserDailyPlanProfile.current(in: modelContext)
        let routineDay = profile?.weeklyRoutine?[weekday]
        let wakeMinutes = routineDay?.wakeMinutes
            ?? profile?.weeklyRoutine?.typicalWakeMinutes
            ?? SupplementDayContext.defaultWakeMinutes
        let bedMinutes = routineDay?.bedMinutes
            ?? profile?.weeklyRoutine?.typicalBedMinutes
            ?? SupplementDayContext.defaultBedMinutes

        let routineTraining = routineDay?.training
        var trainingStart = routineTraining?.startMinutes
        var trainingEnd = routineTraining.map { $0.startMinutes + $0.durationMinutes }
        let isTrainingDay = routineTraining != nil || (planIsTrainingDay ?? false)
        if trainingStart == nil, isTrainingDay {
            // No routine slot but we know it's a training day (plan's day
            // type) — fall back to the user's usual training time-of-day.
            let preference = profile?.trainingTimePreference ?? .anyFree
            let timeOfDay = TrainerSessionReminderScheduler.timeOfDay(for: preference)
            let fallbackStart = timeOfDay.hour * 60 + timeOfDay.minute
            trainingStart = fallbackStart
            trainingEnd = fallbackStart + SupplementDayContext.defaultTrainingDurationMinutes
        }

        // Today's planned meals, reduced to name/number/time.
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return SupplementDayContext(
                planDecisions: planDecisionsByName,
                isTrainingDay: isTrainingDay,
                trainingStartMinutes: trainingStart,
                trainingEndMinutes: trainingEnd,
                wakeMinutes: wakeMinutes,
                bedMinutes: bedMinutes
            )
        }
        let mealDescriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { $0.dayDate >= dayStart && $0.dayDate < nextDayStart }
        )
        let meals = ((try? modelContext.fetch(mealDescriptor)) ?? []).compactMap { meal -> SupplementMealTime? in
            guard let minutes = RoutineTime.minutes(from: meal.scheduledTime) else {
                return nil
            }
            return SupplementMealTime(mealNumber: meal.mealNumber, mealName: meal.mealName, minutes: minutes)
        }

        return SupplementDayContext(
            planDecisions: planDecisionsByName,
            isTrainingDay: isTrainingDay,
            trainingStartMinutes: trainingStart,
            trainingEndMinutes: trainingEnd,
            wakeMinutes: wakeMinutes,
            bedMinutes: bedMinutes,
            meals: meals
        )
    }
}

// MARK: - SupplementReminderScheduler

@MainActor
enum SupplementReminderScheduler {
    /// The in-flight rebuild; each new one waits for it, so a slow cancel
    /// from an earlier call can never delete reminders a later one added.
    private static var latestRebuild: Task<Void, Never>?

    /// Rebuilds today + tomorrow's reminders and checks for a reorder alert.
    /// Safe to call as often as needed.
    static func reschedule(
        notifications: any NotificationServiceProtocol,
        modelContext: ModelContext,
        now: Date = Date()
    ) {
        let previous = latestRebuild
        latestRebuild = Task { @MainActor in
            await previous?.value
            await notifications.cancelSupplementReminders()
            scheduleAll(notifications: notifications, modelContext: modelContext, now: now)
        }
    }

    private static func scheduleAll(
        notifications: any NotificationServiceProtocol,
        modelContext: ModelContext,
        now: Date
    ) {

        let settings = (try? modelContext.fetch(FetchDescriptor<UserSettings>()))?.first
        guard settings?.supplementRemindersEnabled ?? true else {
            return
        }

        let supplements = (try? modelContext.fetch(
            FetchDescriptor<Supplement>(predicate: #Predicate<Supplement> { !$0.isArchived })
        )) ?? []
        guard !supplements.isEmpty else {
            return
        }
        let remindersEnabledByID = Dictionary(uniqueKeysWithValues: supplements.map { ($0.id, $0.remindersEnabled ?? true) })

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for offset in 0 ..< 2 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
                continue
            }
            let context = SupplementDayContext.build(date: date, modelContext: modelContext)
            let doses = SupplementScheduleEngine.schedule(supplements: supplements, context: context)
                .filter { remindersEnabledByID[$0.supplementID] ?? true }
            let groups = SupplementScheduleEngine.group(dosesForDay: doses)

            for group in groups {
                guard let fireDate = calendar.date(bySettingHour: group.minutes / 60, minute: group.minutes % 60, second: 0, of: date),
                      fireDate > now
                else {
                    continue
                }
                let (title, body) = content(for: group)
                notifications.scheduleSupplementReminder(
                    title: title,
                    body: body,
                    fireDate: fireDate,
                    supplementNames: group.names
                )
            }
        }

        checkReorderAlerts(supplements: supplements, modelContext: modelContext, notifications: notifications, now: now)
    }

    /// "Breakfast: Creatine + Vitamin D3" — the time slot's anchor label
    /// (falling back to a plain clock time for a pinned dose with no anchor),
    /// then every supplement due at that moment. Short, drill-sergeant body.
    private static func content(for group: SupplementDoseGroup) -> (title: String, body: String) {
        let label = group.doses.first?.anchor?.groupLabel ?? group.timeLabel
        let names = group.names.joined(separator: " + ")
        let body = group.doses.count == 1 ? "Take it now. No excuses." : "Take them now. No excuses."
        return ("\(label): \(names)", body)
    }

    // MARK: - Reorder alerts

    private static func checkReorderAlerts(
        supplements: [Supplement],
        modelContext: ModelContext,
        notifications: any NotificationServiceProtocol,
        now: Date
    ) {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -SupplementReorderService.intakeWindowDays, to: now) ?? now
        let logDescriptor = FetchDescriptor<SupplementIntakeLog>(
            predicate: #Predicate<SupplementIntakeLog> { $0.day >= windowStart }
        )
        let recentLogs = (try? modelContext.fetch(logDescriptor)) ?? []

        var didAlert = false
        for supplement in supplements {
            guard SupplementReorderService.shouldSendReorderAlert(for: supplement, recentLogs: recentLogs, asOf: now, calendar: calendar)
            else {
                continue
            }
            let daysLeft = SupplementReorderService.daysLeft(for: supplement, recentLogs: recentLogs, asOf: now, calendar: calendar) ?? 0
            let title = "\(supplement.name) is running out"
            let body = daysLeft <= 0
                ? "You're out. Restock before you miss a dose."
                : "About \(daysLeft) day\(daysLeft == 1 ? "" : "s") left. Order it now, not the day it runs out."
            notifications.scheduleSupplementReorderAlert(supplementName: supplement.name, title: title, body: body)
            supplement.lastReorderAlertAt = now
            didAlert = true
        }
        if didAlert {
            try? modelContext.save()
        }
    }

    // MARK: - Notification action support

    /// Marks every named supplement taken TODAY — the "Taken" notification
    /// action. Idempotent (a name already marked taken today is skipped) and
    /// applies the same reorder decrement `NutritionTabViewModel.
    /// toggleSupplementTaken` does, so the shelf count stays correct whether
    /// the tap happened in-app or from the notification.
    static func markTaken(names: [String], modelContext: ModelContext, now: Date = Date()) {
        let today = Calendar.current.startOfDay(for: now)
        var didChange = false
        for name in names {
            let logDescriptor = FetchDescriptor<SupplementIntakeLog>(
                predicate: #Predicate<SupplementIntakeLog> { $0.day == today && $0.supplementName == name }
            )
            let existing = (try? modelContext.fetch(logDescriptor)) ?? []
            guard existing.isEmpty else {
                continue
            }
            modelContext.insert(SupplementIntakeLog(supplementName: name, day: today))
            let supplementDescriptor = FetchDescriptor<Supplement>(
                predicate: #Predicate<Supplement> { $0.name == name }
            )
            if let supplement = (try? modelContext.fetch(supplementDescriptor))?.first {
                SupplementReorderService.applyTaken(to: supplement)
            }
            didChange = true
        }
        guard didChange else {
            return
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
    }
}

// MARK: - SupplementTimingAnchor + notification grouping label

private extension SupplementTimingAnchor {
    /// Short label for a grouped reminder title — "Breakfast", not "With breakfast".
    var groupLabel: String {
        switch self {
        case .wake: "Wake up"
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .preTraining: "Pre-training"
        case .postTraining: "Post-training"
        case .bedtime: "Bedtime"
        }
    }
}
