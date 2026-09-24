//
// TrainerSessionReminderScheduler.swift
// Tempo
//
// Fix #12 — local-notification reminders for the active TrainerProgram's
// upcoming sessions. Rebuilds a rolling 7-day window every time it's called:
// cancels every pending trainer-session reminder, then re-derives which of
// the next 7 days actually run a trainer session from Training's REAL week
// (`TrainingScheduleProvider` — the exact generation path Today/Week Plan
// use), so a session paused by red recovery or a fixed match day correctly
// gets NO reminder even though the program nominally schedules one that
// weekday. One reminder per active session, at the user's usual training
// time (`UserDailyPlanProfile.trainingTimePreference`, falling back to
// 17:00 for `.anyFree` or when no profile exists yet).
//
// Callers: ContentView (on `.tempoTrainingSettingsChanged` /
// `.tempoWorkoutChanged`, debounced, and once on first load) and TempoApp
// (on app foreground) — see both files' `.onReceive`/`.onChange(of:
// scenePhase)`.
//

import Foundation
import SwiftData

// MARK: - TrainerSessionReminderScheduler

@MainActor
enum TrainerSessionReminderScheduler {
    static let lookaheadDays = 7

    /// Rebuild the rolling window. Safe to call as often as needed — it's
    /// always a full cancel + rebuild, never an incremental diff, so a
    /// mid-window settings change or program edit can't leave stale
    /// reminders behind.
    static func reschedule(
        notifications: any NotificationServiceProtocol,
        trainingEngine: any TrainingEngineProtocol,
        whoop: any WhoopServiceProtocol,
        healthKit: any HealthKitServiceProtocol,
        modelContext: ModelContext,
        now: Date = Date()
    ) {
        notifications.cancelTrainerSessionReminders()

        guard let settings = (try? modelContext.fetch(FetchDescriptor<UserSettings>()))?.first,
              settings.trainingReminderEnabled,
              settings.trainerSessionReminderEnabled
        else {
            return
        }

        let vm = TrainingViewModel(trainingEngine: trainingEngine, whoop: whoop, healthKit: healthKit)
        guard let program = vm.activeTrainerProgram(modelContext: modelContext) else {
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let preference = (try? modelContext.fetch(FetchDescriptor<UserDailyPlanProfile>()))?
            .first?.trainingTimePreference ?? .anyFree
        let timeOfDay = Self.timeOfDay(for: preference)

        // Cache each real week's schedule (at most 2 distinct ISO weeks fall
        // inside a 7-day lookahead) instead of recomputing it per day.
        var scheduleByWeekStart: [Date: [DayTrainingSchedule]] = [:]

        for offset in 0 ..< lookaheadDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
                continue
            }
            let weekStart = TrainingCalendar.mondayOfWeek(containing: date)
            let weekSchedule: [DayTrainingSchedule] = if let cached = scheduleByWeekStart[weekStart] {
                cached
            } else {
                TrainingScheduleProvider.weekSchedule(
                    containing: date,
                    trainingEngine: trainingEngine,
                    whoop: whoop,
                    healthKit: healthKit,
                    modelContext: modelContext
                )
            }
            scheduleByWeekStart[weekStart] = weekSchedule

            guard let day = weekSchedule.first(where: { calendar.isDate($0.date, inSameDayAs: date) }),
                  day.isTrainerSession,
                  let session = program.session(on: date),
                  let fireDate = Self.fireDate(on: date, timeOfDay: timeOfDay, calendar: calendar),
                  fireDate > now
            else {
                continue
            }

            let sessionKey = program.sessionKey(weekIndex: session.weekIndex, dayIndex: session.dayIndex)
            let (title, body) = Self.content(for: session.day, timeOfDay: timeOfDay)
            notifications.scheduleTrainerSessionReminder(
                sessionKey: sessionKey,
                date: date,
                title: title,
                body: body,
                fireDate: fireDate
            )
        }
    }

    // MARK: - Training time of day

    /// The category-based onboarding preference has no exact clock time —
    /// pick a representative hour inside each daypart
    /// (`CalendarService.preferredDaypart` uses the same 8/12/17 boundaries
    /// for morning/midday/evening); `.anyFree` and no profile fall back to
    /// 17:00, the most common after-work/after-school training slot.
    static func timeOfDay(for preference: TrainingTimePreference) -> (hour: Int, minute: Int) {
        switch preference {
        case .morning: (8, 0)
        case .midday: (12, 0)
        case .evening: (17, 0)
        case .anyFree: (17, 0)
        }
    }

    private static func fireDate(on date: Date, timeOfDay: (hour: Int, minute: Int), calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: timeOfDay.hour, minute: timeOfDay.minute, second: 0, of: date)
    }

    // MARK: - Content

    /// "Lifting 2 at 17:00 — 4 supersets, ~50 min" (strength) / "Aerobic Run
    /// today — 50' — 2' slow / 1' fast / 30" walk" (conditioning, verbatim
    /// trainer prescription). Title carries the em-dash-left half, body the
    /// right.
    static func content(for day: ProgramDay, timeOfDay: (hour: Int, minute: Int)) -> (title: String, body: String) {
        let time = String(format: "%02d:%02d", timeOfDay.hour, timeOfDay.minute)
        let label = day.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? day.workoutType.displayName

        guard day.isStrength else {
            let detail = day.exercises.first?.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? day.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Today's session from your trainer."
            return ("\(label) today", detail)
        }

        let supersets = Set(day.exercises.compactMap(\.group)).count
        let minutes = Self.estimatedMinutes(for: day)
        let detail = supersets > 0
            ? "\(supersets) superset\(supersets == 1 ? "" : "s"), ~\(minutes) min"
            : "\(day.exercises.count) exercise\(day.exercises.count == 1 ? "" : "s"), ~\(minutes) min"
        return ("\(label) at \(time)", detail)
    }

    /// Rough estimate from sets alone (this runs on the raw imported
    /// `ProgramDay`, before any `PlannedSet` exists to measure) — 5 min
    /// warmup + ~2.5 min per working set (work + rest), the same rate
    /// `TodayWorkoutView.estimatedDuration` uses for compound working sets.
    private static func estimatedMinutes(for day: ProgramDay) -> Int {
        guard !day.exercises.isEmpty else {
            return 30
        }
        let totalSets = day.exercises.reduce(0) { $0 + max(1, $1.sets) }
        return Int((5 + Double(totalSets) * 2.5).rounded())
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
