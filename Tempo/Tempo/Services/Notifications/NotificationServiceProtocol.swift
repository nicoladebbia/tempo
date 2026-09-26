//
// NotificationServiceProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - EscalationTier

enum EscalationTier: String, CaseIterable {
    case gentle
    case firm
    case urgent
    case critical
}

// MARK: - BriefingContent

struct BriefingContent {
    let recoveryScore: Double?
    let workoutType: String?
    let nonNegotiablesCount: Int
    let topPriority: String
}

// MARK: - ScheduledNotification

struct ScheduledNotification {
    let category: String
    let title: String
    let body: String
    let triggerDate: Date
}

// MARK: - NotificationServiceProtocol

protocol NotificationServiceProtocol: Sendable {
    func requestAuthorization() async throws -> Bool
    func scheduleMorningBriefing(for date: Date, content: BriefingContent)
    func scheduleAccountabilityEscalation(tier: EscalationTier, time: Date, content: String)
    func scheduleMealReminder(mealName: String, time: Date)
    func scheduleBedtimeReminder(time: Date)

    /// Time Sensitive APNs reminder to move a frozen ingredient out of the freezer
    /// so it defrosts in time for mealtime. Identifier scheme is deterministic
    /// (`defrost_<mealID>_<ingredientID>`) so reschedules + cancels can target
    /// the exact pending request.
    func scheduleDefrostReminder(
        mealID: UUID,
        ingredientID: UUID,
        ingredientName: String,
        mealName: String,
        leadTimeHours: Int,
        fireDate: Date
    )

    /// Cancel every pending defrost reminder scheduled for `mealID`. Called when
    /// a meal is eaten, skipped, deleted, or rescheduled.
    func cancelDefrostReminders(forMealID mealID: UUID)

    /// "Start prepping now" reminder fired at the meal's prep-start time
    /// (meal − prepMinutes − cookMinutes). Identifier `prepstart_<mealID>`.
    func schedulePrepStartReminder(
        mealID: UUID,
        mealName: String,
        prepStartDate: Date
    )

    /// Cancel the prep-start reminder for `mealID`. Called alongside defrost
    /// cancellation when a meal is eaten / skipped / rescheduled.
    func cancelPrepStartReminder(forMealID mealID: UUID)

    /// "Have you done your breakfast?" check-in. Fires `lateMinutes` after
    /// the meal's scheduled time if the user hasn't marked it eaten/skipped.
    /// Identifier `overdue_<mealID>` so reschedules + cancels target the
    /// exact pending request. Called every time a meal is created or its
    /// scheduled time shifts; cancelled on eaten / skipped / deleted.
    func scheduleOverdueMealReminder(
        mealID: UUID,
        mealName: String,
        scheduledTime: Date,
        lateMinutes: Int
    )

    /// Cancel the overdue reminder for `mealID`.
    func cancelOverdueMealReminder(forMealID mealID: UUID)

    /// Fix #12 — reminder for one active-TrainerProgram session (Training's
    /// REAL week, after recovery/match pauses). `sessionKey` is
    /// `TrainerProgram.sessionKey(weekIndex:dayIndex:)`; the identifier is
    /// derived from it plus `date` so a repeating 1-week program's same
    /// weekday gets a fresh id every real calendar week, and rescheduling the
    /// SAME date is idempotent (remove + add lands on the same id). Unlike
    /// the other reminders here this is deliberately scheduled up to 7 days
    /// out — see `TrainerSessionReminderScheduler`.
    func scheduleTrainerSessionReminder(sessionKey: String, date: Date, title: String, body: String, fireDate: Date)

    /// Cancel every pending trainer-session reminder — called before
    /// rebuilding the rolling 7-day window.
    func cancelTrainerSessionReminders()

    /// Weekly-upload feature — Sunday 19:00 "New week from your trainer —
    /// upload it so Monday's ready." Stable identifier: always reschedules
    /// in place (see `WeeklyUploadReminderScheduler`), never accumulates.
    func scheduleWeeklyUploadSundayReminder(programName: String, fireDate: Date)

    /// The Monday 08:00 "still not uploaded" follow-up nudge. Stable
    /// identifier, same rebuild pattern as the Sunday reminder.
    func scheduleWeeklyUploadMondayReminder(programName: String, fireDate: Date)

    /// Cancel both weekly-upload reminders — called before rebuilding them,
    /// and once the upcoming week's program exists.
    func cancelWeeklyUploadReminders()

    func cancelAll()
    func cancelCategory(_ category: String)
}
