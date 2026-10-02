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
import UserNotifications

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
        // The AI can repeat a name within a day — never trap on it (first wins).
        let planDecisionsByName = Dictionary(
            (plan?.supplementDecisions[weekday] ?? []).map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
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
            // A ticked dose's own "Supplements" entry is not a meal to time doses around.
            guard !EatenMealRecorder.isSupplementDose(meal), let minutes = RoutineTime.minutes(from: meal.scheduledTime) else {
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
            await rebuild(notifications: notifications, modelContext: modelContext, now: now)
        }
    }

    /// Cancel + rebuild, awaitable (tests; `reschedule` wraps it in a queued task).
    static func rebuild(
        notifications: any NotificationServiceProtocol,
        modelContext: ModelContext,
        now: Date = Date()
    ) async {
        await notifications.cancelSupplementReminders()
        await clearSnoozes(
            takenIDs: SupplementIntakeStore.takenIDs(on: now, in: modelContext),
            center: UNUserNotificationCenter.current()
        )
        scheduleAll(notifications: notifications, modelContext: modelContext, now: now)
    }

    // MARK: - Snoozed reminders

    /// Identifier prefix of a snoozed supplement reminder:
    /// `snooze_supp_<uuid>_<id1>,<id2>…` (the IDs of the supplements it lists).
    static let snoozePrefix = "snooze_supp_"

    static func snoozeIdentifier(supplementIDs: [String]) -> String {
        "\(snoozePrefix)\(UUID().uuidString)_\(supplementIDs.joined(separator: ","))"
    }

    /// Snoozed reminders whose every supplement is already taken — they'd
    /// otherwise still fire after the dose was ticked.
    static func snoozeIdentifiersToRemove(pending: [String], takenIDs: Set<UUID>) -> [String] {
        pending.filter { identifier in
            guard identifier.hasPrefix(snoozePrefix) else {
                return false
            }
            let parts = identifier.dropFirst(snoozePrefix.count).split(separator: "_", maxSplits: 1)
            guard parts.count == 2 else {
                return false
            }
            let ids = parts[1].split(separator: ",").compactMap { UUID(uuidString: String($0)) }
            return !ids.isEmpty && ids.allSatisfy(takenIDs.contains)
        }
    }

    static func clearSnoozes(takenIDs: Set<UUID>, center: UNUserNotificationCenter) async {
        guard !takenIDs.isEmpty else {
            return
        }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let stale = snoozeIdentifiersToRemove(pending: pending, takenIDs: takenIDs)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
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
        let remindersEnabledByID = Dictionary(
            supplements.map { ($0.id, $0.remindersEnabled ?? true) },
            uniquingKeysWith: { first, _ in first }
        )
        SupplementIntakeStore.backfillIDs(in: modelContext)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for offset in 0 ..< 2 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
                continue
            }
            let context = SupplementDayContext.build(date: date, modelContext: modelContext)
            // A dose already taken today needs no reminder (the rebuild runs
            // after every taken toggle, so a tick must silence what's left).
            let takenIDs = SupplementIntakeStore.takenIDs(on: date, in: modelContext)
            let doses = SupplementScheduleEngine.schedule(supplements: supplements, context: context)
                .filter { remindersEnabledByID[$0.supplementID] ?? true }
                .filter { !takenIDs.contains($0.supplementID) }
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
                    supplementNames: group.names,
                    supplementIDs: group.doses.map { $0.supplementID.uuidString }
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
        let windowStart = SupplementReorderService.intakeWindowStart(asOf: now, calendar: calendar)
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
            notifications.scheduleSupplementReorderAlert(
                supplementName: supplement.name, supplementID: supplement.id.uuidString, title: title, body: body
            )
            supplement.lastReorderAlertAt = now
            didAlert = true
        }
        if didAlert {
            try? modelContext.save()
        }
    }

    // MARK: - Notification action support

    /// Marks every listed supplement taken TODAY — the "Taken" notification
    /// action. Idempotent and applies the same reorder decrement
    /// `NutritionTabViewModel.toggleSupplementTaken` does, so the shelf count
    /// stays correct whether the tap happened in-app or from the notification.
    ///
    /// `ids` (parallel to `names`) are the shelf items' UUID strings; a
    /// notification scheduled before IDs existed carries only names, so each
    /// entry falls back to the name when its ID is missing/unparseable.
    static func markTaken(names: [String], ids: [String] = [], modelContext: ModelContext, now: Date = Date()) {
        var didChange = false
        for (index, name) in names.enumerated() {
            let id = ids.indices.contains(index) ? UUID(uuidString: ids[index]) : nil
            if SupplementIntakeStore.markTaken(supplementID: id, name: name, day: now, in: modelContext) {
                didChange = true
            }
        }
        guard didChange else {
            return
        }
        try? modelContext.save()
        let takenIDs = SupplementIntakeStore.takenIDs(on: now, in: modelContext)
        Task { await clearSnoozes(takenIDs: takenIDs, center: UNUserNotificationCenter.current()) }
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
