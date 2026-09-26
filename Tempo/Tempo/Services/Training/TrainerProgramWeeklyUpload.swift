//
// TrainerProgramWeeklyUpload.swift
// Tempo
//
// Weekly-upload feature — pure decision logic shared by the "New week —
// upload" card (WeeklyUploadPromptCard), its two push reminders
// (WeeklyUploadReminderScheduler), and the review screen's auto start/queue
// choice when a new weekly program replaces the old one
// (TrainerProgramReviewView). Kept free of SwiftUI/SwiftData/NotificationCenter
// so every rule here is unit-testable with an injected `now` — see CLAUDE.md:
// "we already had date/time-of-day-dependent test failures twice this week."
//
// Anchoring rule: `isDue` is computed from the ACTIVE program's own
// `startDate` week ("served week"), never from `now`'s calendar week — a
// single fixed Sunday-19:00 deadline for as long as the same program stays
// active, so once `now` passes it, the card stays showing no matter how many
// further weeks go by with nothing uploaded (no "already overdue" special
// case needed there).
//
// Everything with a real-world side effect once overdue — the push
// reminders' one-shot fire dates, and "is the upcoming week covered" —
// instead uses `effectiveWeekMonday` (the served week ROLLED FORWARD to
// `now`'s own calendar week once stale). Anchoring those to the original,
// increasingly-distant served week would mean: the one-shot Sunday/Monday
// reminders both fall further into the past every week and NEVER get
// rescheduled again after the first miss (their `fireDate > now` guard just
// keeps failing forever) — the opposite of a drill-sergeant nag — and a
// legitimately-queued new upload (whose `startDate` is computed off the
// REAL current week, see `uploadTiming`) would never register as "covering"
// a week that's still being measured from months ago.
//

import Foundation

// MARK: - TrainerProgramWeeklyUpload

enum TrainerProgramWeeklyUpload {
    static let deadlineHour = 19
    static let mondayNudgeHour = 8

    /// Sunday 19:00 local of the week that starts on `weekMonday`.
    static func sundayDeadline(afterWeekStarting weekMonday: Date, calendar: Calendar = TrainingCalendar.iso8601) -> Date {
        let sunday = calendar.date(byAdding: .day, value: 6, to: weekMonday) ?? weekMonday
        return calendar.date(bySettingHour: deadlineHour, minute: 0, second: 0, of: sunday) ?? sunday
    }

    /// Monday 08:00 local of the week right after `weekMonday` — the
    /// "still not uploaded" morning nudge.
    static func mondayNudge(afterWeekStarting weekMonday: Date, calendar: Calendar = TrainingCalendar.iso8601) -> Date {
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: weekMonday) ?? weekMonday
        return calendar.date(bySettingHour: mondayNudgeHour, minute: 0, second: 0, of: nextMonday) ?? nextMonday
    }

    /// The Monday of the week `program` is currently serving.
    static func servedWeekMonday(for program: TrainerProgram, calendar: Calendar = TrainingCalendar.iso8601) -> Date {
        TrainingCalendar.mondayOfWeek(containing: program.startDate)
    }

    /// `servedWeekMonday`, rolled forward to `now`'s own calendar week once
    /// the served week has gone stale (program can't start in the future
    /// while active, so this is just `max`). Used for anything that needs a
    /// FUTURE fire date or a real "which week is next" answer — never for
    /// `isDue`, which must stay anchored to the original served week so it
    /// keeps reading true once passed. See this file's header.
    static func effectiveWeekMonday(for program: TrainerProgram, now: Date, calendar: Calendar = TrainingCalendar.iso8601) -> Date {
        max(servedWeekMonday(for: program, calendar: calendar), TrainingCalendar.mondayOfWeek(containing: now))
    }

    /// True once `now` reaches (or passes) the served week's Sunday-19:00
    /// deadline. Not gated on cadence — callers check `program.cadence` first
    /// (kept separate so a caller can also use this for a program that just
    /// changed cadence mid-flight without this silently no-op'ing).
    static func isDue(activeProgram: TrainerProgram, now: Date, calendar: Calendar = TrainingCalendar.iso8601) -> Bool {
        guard activeProgram.cadence == .weekly else {
            return false
        }
        let deadline = sundayDeadline(afterWeekStarting: servedWeekMonday(for: activeProgram, calendar: calendar), calendar: calendar)
        return now >= deadline
    }

    /// True once some program (active or queued) already covers `now`'s
    /// current or next real calendar week — either already active with a
    /// fresh `startDate` (a Mon–Fri upload, in which case `activeProgram`
    /// itself IS that program and `isDue` already reads not-yet-due for it),
    /// or queued to auto-activate next Monday. Deliberately measured from
    /// `now`, NOT from `activeProgram`'s (possibly long-stale) served week —
    /// a legitimate new upload's own `startDate` is always computed off the
    /// REAL current week (`uploadTiming`), so checking against a frozen past
    /// week would never recognize it as covering anything once overdue.
    static func isUpcomingWeekCovered(
        programs: [TrainerProgram],
        activeProgram: TrainerProgram,
        now: Date,
        calendar: Calendar = TrainingCalendar.iso8601
    ) -> Bool {
        let currentWeekMonday = TrainingCalendar.mondayOfWeek(containing: now)
        let nextWeekMonday = calendar.date(byAdding: .day, value: 7, to: currentWeekMonday) ?? currentWeekMonday
        return programs.contains { candidate in
            guard candidate.id != activeProgram.id else {
                return false
            }
            let candidateWeekMonday = TrainingCalendar.mondayOfWeek(containing: candidate.startDate)
            return candidateWeekMonday == currentWeekMonday || candidateWeekMonday == nextWeekMonday
        }
    }

    /// The single check the card and the reminder scheduler both use.
    static func shouldPromptUpload(
        programs: [TrainerProgram],
        activeProgram: TrainerProgram,
        now: Date,
        calendar: Calendar = TrainingCalendar.iso8601
    ) -> Bool {
        isDue(activeProgram: activeProgram, now: now, calendar: calendar)
            && !isUpcomingWeekCovered(programs: programs, activeProgram: activeProgram, now: now, calendar: calendar)
    }

    // MARK: - Review screen: auto start/queue decision (fix #5)

    /// A brand-new weekly program, saved while another program is active,
    /// replaces it either immediately or next Monday, decided purely by the
    /// upload's own weekday — never a manual picker (unlike a `.block`
    /// import's "starts now / after current / on a date" choice).
    struct UploadTiming: Equatable {
        let startDate: Date
        /// Non-nil (== `startDate`) means this program is QUEUED, not
        /// immediately active — see `TrainerProgramSaver.save`.
        let queuedActivationDate: Date?

        var isQueued: Bool {
            queuedActivationDate != nil
        }
    }

    /// Saturday(6)/Sunday(7) — the trainer's send belongs to the week that's
    /// ending, so the new program queues for NEXT Monday and the old one
    /// keeps running until then. Monday–Friday(1–5) — starts THIS Monday and
    /// replaces the old program right away.
    static func uploadTiming(forUploadOn uploadDate: Date, calendar: Calendar = TrainingCalendar.iso8601) -> UploadTiming {
        let weekday = TrainerProgram.isoWeekday(of: uploadDate) // 1 = Mon … 7 = Sun
        let thisMonday = TrainingCalendar.mondayOfWeek(containing: uploadDate)
        guard weekday >= 6 else {
            return UploadTiming(startDate: thisMonday, queuedActivationDate: nil)
        }
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: thisMonday) ?? thisMonday
        return UploadTiming(startDate: nextMonday, queuedActivationDate: nextMonday)
    }
}
