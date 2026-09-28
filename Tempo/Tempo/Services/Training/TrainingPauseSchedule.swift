//
// TrainingPauseSchedule.swift
// Tempo
//
// Pure, unit-tested logic for the pause/travel-pain feature's pause half.
// Free of SwiftData/SwiftUI so every rule here is testable with injected
// dates (CLAUDE.md: "we already had date/time-of-day-dependent test failures
// twice this week") — same discipline as `TrainerProgramWeeklyUpload.swift`.
//
// Single choke point: `apply(_:to:calendar:)` runs in the SAME two places
// `TrainingViewModel.applyTrainerProgram` already runs (`assembleWeekPlans`
// and the single-day `generateAndPersist` fallback) — every reader that
// already trusts `WorkoutPlan.type`/`programSessionKey` (Nutrition via
// `TrainingScheduleProvider`, `TrainerSessionReminderScheduler`,
// `MissedTrainerSessionCard`) inherits the pause for free, with zero changes
// of their own. See each file's own pause-awareness note where one was still
// needed (`missedFixedSession`, `weeklyUploadDue`).
//

import Foundation

// MARK: - TrainingPauseSchedule

enum TrainingPauseSchedule {
    /// The pause (if any) that covers `date`. A pause covers `date` when:
    /// - `date`'s start-of-day is on/after `startDate`, AND
    /// - it's on/before `plannedEndDate` (nil = no upper bound), AND
    /// - it wasn't manually resumed strictly before `date` (a "Resume now"
    ///   tap ends coverage from that calendar day forward, but the day it
    ///   happened on was already decided by whatever ran earlier that day —
    ///   this mirrors `TrainerProgram.applyTrainerProgram`'s own
    ///   day-granularity semantics, never a same-day take-back).
    ///
    /// When several pauses somehow overlap the same day (shouldn't normally
    /// happen — the UI only lets one be active at a time), the most recently
    /// created one wins, so a corrective re-pause always takes precedence.
    nonisolated static func coveringPause(
        _ pauses: [TrainingPause],
        on date: Date,
        calendar: Calendar = .current
    ) -> TrainingPause? {
        let day = calendar.startOfDay(for: date)
        return pauses
            .filter { pause in
                guard day >= pause.startDate else {
                    return false
                }
                if let end = pause.plannedEndDate, day > end {
                    return false
                }
                if let resumedAt = pause.resumedAt, day >= calendar.startOfDay(for: resumedAt) {
                    return false
                }
                return true
            }
            .max { $0.createdAt < $1.createdAt }
    }

    /// Overlay pauses onto already-generated plans, mutating in place — the
    /// exact sibling of `TrainingViewModel.applyTrainerProgram`'s match-day
    /// branch, called right after it at both its call sites.
    ///
    /// Deliberately conservative about WHAT it overrides:
    /// - never touches a `.football` day (a recurring/fixed commitment, same
    ///   priority `applyTrainerProgram` already gives a dated match);
    /// - never touches a non-`.planned` row (started/completed/skipped work
    ///   is sacred — same invariant `PlanResolution` enforces elsewhere);
    /// - clears any trainer-program keys so `TrainingScheduleProvider` reports
    ///   `isTrainerSession == false` for the day (this is what makes the
    ///   session-reminder scheduler and the missed-session card both go quiet
    ///   with zero changes of their own — see file header).
    nonisolated static func apply(
        _ pauses: [TrainingPause],
        to plans: [WorkoutPlan],
        calendar: Calendar = .current
    ) {
        guard !pauses.isEmpty else {
            return
        }
        for plan in plans {
            guard plan.status == .planned, plan.type != .football,
                  let pause = coveringPause(pauses, on: plan.date, calendar: calendar)
            else {
                continue
            }
            plan.type = .rest
            plan.programSessionKey = nil
            plan.programSecondaryKey = nil
            plan.secondarySessionType = nil
            plan.pausedReasonRaw = pause.reason.rawValue
            plan.notes = "Paused — \(pause.reason.reportLabel.lowercased())."
        }
    }

    /// True when EVERY day of the ISO week starting `weekMonday` is covered
    /// by some pause — the "upload nudge pauses during a pause that covers
    /// the whole week" rule (`TrainingViewModel.weeklyUploadDue`). Football
    /// days are exempt from `apply`'s own override, but a whole-week pause
    /// still legitimately means "don't nag for a new program" even if one
    /// day is a scheduled match — the athlete isn't uploading a program
    /// while sick/away regardless.
    nonisolated static func pausesCoverWholeWeek(
        pauses: [TrainingPause],
        weekMonday: Date,
        calendar: Calendar = TrainingCalendar.iso8601
    ) -> Bool {
        guard !pauses.isEmpty else {
            return false
        }
        for offset in 0 ..< 7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekMonday),
                  coveringPause(pauses, on: day, calendar: calendar) != nil
            else {
                return false
            }
        }
        return true
    }

    /// Whole days paused, from `pause.startDate` up to (and including) the
    /// day before `resumeDay` — the count `shiftedStartDate` shifts a
    /// fixed-mode program's `startDate` by.
    nonisolated static func pausedDayCount(
        _ pause: TrainingPause,
        resumeDay: Date,
        calendar: Calendar = .current
    ) -> Int {
        let start = calendar.startOfDay(for: pause.startDate)
        let resume = calendar.startOfDay(for: resumeDay)
        let days = calendar.dateComponents([.day], from: start, to: resume).day ?? 0
        return max(0, days)
    }

    /// `.shiftForward` resume strategy (fixed mode only) — push `startDate`
    /// forward by exactly the number of paused calendar days. `TrainerProgram
    /// .weekIndex(on:)` is `(days since startDate) / 7`; shifting BOTH the
    /// reference date (implicitly, by resuming "today") and `startDate` by
    /// the same amount keeps `weekIndex(on: resumeDay)` equal to what
    /// `weekIndex(on: pause.startDate)` was — i.e. the athlete comes back
    /// into the SAME program week they paused in, just later, instead of the
    /// week the raw calendar would otherwise suggest. The trainer's own
    /// weekday layout (which weekday carries which session) is untouched —
    /// only WHICH WEEK applies shifts.
    nonisolated static func shiftedStartDate(
        for program: TrainerProgram,
        pausedDays: Int,
        calendar: Calendar = TrainingCalendar.iso8601
    ) -> Date {
        calendar.date(byAdding: .day, value: pausedDays, to: program.startDate) ?? program.startDate
    }
}
