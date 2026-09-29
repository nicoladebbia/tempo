//
// WeeklyUploadReminderScheduler.swift
// Tempo
//
// Weekly-upload feature — local-notification reminders to upload the
// trainer's next weekly program: Sunday 19:00 ("new week — upload it"), and a
// Monday 08:00 follow-up if it still hasn't landed. Always a full cancel +
// rebuild (mirrors TrainerSessionReminderScheduler) so a program edit or
// settings toggle mid-week can't leave a stale reminder behind. Gated behind
// `trainingReminderEnabled` (global) and `weeklyUploadReminderEnabled`
// (sibling of `trainerSessionReminderEnabled` — see UserSettings).
//
// Callers: ContentView (on `.tempoTrainingSettingsChanged`/
// `.tempoWorkoutChanged`, debounced, and once on first load) and TempoApp (on
// app foreground) — same hooks as TrainerSessionReminderScheduler.
//

import Foundation
import SwiftData

// MARK: - WeeklyUploadReminderScheduler

@MainActor
enum WeeklyUploadReminderScheduler {
    /// Rebuild both reminders. Safe to call as often as needed.
    static func reschedule(
        notifications: any NotificationServiceProtocol,
        trainingEngine: any TrainingEngineProtocol,
        whoop: any WhoopServiceProtocol,
        healthKit: any HealthKitServiceProtocol,
        modelContext: ModelContext,
        now: Date = Date()
    ) {
        notifications.cancelWeeklyUploadReminders()

        guard let settings = (try? modelContext.fetch(FetchDescriptor<UserSettings>()))?.first,
              settings.trainingReminderEnabled,
              settings.weeklyUploadReminderEnabled
        else {
            return
        }

        let vm = TrainingViewModel(trainingEngine: trainingEngine, whoop: whoop, healthKit: healthKit)
        guard let program = vm.activeTrainerProgram(modelContext: modelContext), program.cadence == .weekly else {
            return
        }

        // "cancel both once the upcoming week's program exists" — already
        // cancelled above; simply don't reschedule.
        let all = (try? modelContext.fetch(FetchDescriptor<TrainerProgram>())) ?? []
        guard !TrainerProgramWeeklyUpload.isUpcomingWeekCovered(programs: all, activeProgram: program, now: now) else {
            return
        }

        // Rolled forward to `now`'s own week once stale — a one-shot fire
        // date anchored to the ORIGINAL served week would fall further into
        // the past every week the athlete keeps ignoring it, and once both
        // guards below fail it would never be rescheduled again. This keeps
        // nagging every week for as long as nothing gets uploaded.
        let anchorWeekMonday = TrainerProgramWeeklyUpload.effectiveWeekMonday(for: program, now: now)
        let sundayFire = TrainerProgramWeeklyUpload.sundayDeadline(afterWeekStarting: anchorWeekMonday)
        let mondayFire = TrainerProgramWeeklyUpload.mondayNudge(afterWeekStarting: anchorWeekMonday)

        // Pause/travel-pain feature — no nagging to upload while away/sick: a
        // reminder that would fire ON a paused day is dropped, and a pause
        // covering the whole week being uploaded for drops both (same rule
        // as `weeklyUploadDue`'s in-app prompt).
        let pauses = vm.fetchTrainingPauses(modelContext: modelContext)
        let nextWeekMonday = TrainingCalendar.iso8601.date(byAdding: .day, value: 7, to: anchorWeekMonday) ?? anchorWeekMonday
        if TrainingPauseSchedule.pausesCoverWholeWeek(pauses: pauses, weekMonday: nextWeekMonday) {
            return
        }
        let sundayPaused = TrainingPauseSchedule.coveringPause(pauses, on: sundayFire) != nil
        let mondayPaused = TrainingPauseSchedule.coveringPause(pauses, on: mondayFire) != nil

        if sundayFire > now, !sundayPaused {
            notifications.scheduleWeeklyUploadSundayReminder(programName: program.name, fireDate: sundayFire)
        }
        if mondayFire > now, !mondayPaused {
            notifications.scheduleWeeklyUploadMondayReminder(programName: program.name, fireDate: mondayFire)
        }
    }
}
