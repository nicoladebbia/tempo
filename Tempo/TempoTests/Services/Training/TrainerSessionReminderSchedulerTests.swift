//
// TrainerSessionReminderSchedulerTests.swift
// Tempo
//
// Fix #12 — pins which of the next 7 days get a trainer-session reminder
// (recovery/match pauses excluded via Training's real week), that the
// scheduled identifier is stable across a reschedule, the notification
// content, and that the master toggles gate scheduling entirely.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainerSessionReminderSchedulerTests: XCTestCase {
    // MARK: - Pure content helpers (no ModelContext needed)

    func testTimeOfDayMapsPreferenceToAnHour() {
        func assertHourMinute(_ preference: TrainingTimePreference, _ hour: Int, _ minute: Int, line: UInt = #line) {
            let result = TrainerSessionReminderScheduler.timeOfDay(for: preference)
            XCTAssertEqual(result.hour, hour, line: line)
            XCTAssertEqual(result.minute, minute, line: line)
        }
        assertHourMinute(.morning, 8, 0)
        assertHourMinute(.midday, 12, 0)
        assertHourMinute(.evening, 17, 0)
        assertHourMinute(.anyFree, 17, 0)
    }

    func testContentForStrengthDayWithSupersets() {
        let day = ProgramDay(
            weekday: 1, title: "Lifting 2", focus: "push",
            exercises: [
                ProgramExercise(name: "Bench", sets: 3, repsLow: 8, group: 1),
                ProgramExercise(name: "Row", sets: 3, repsLow: 8, group: 1),
                ProgramExercise(name: "OHP", sets: 3, repsLow: 8, group: 2),
                ProgramExercise(name: "Pulldown", sets: 3, repsLow: 8, group: 2),
            ]
        )
        let (title, body) = TrainerSessionReminderScheduler.content(for: day, timeOfDay: (17, 0))
        XCTAssertEqual(title, "Lifting 2 at 17:00")
        XCTAssertEqual(body, "2 supersets, ~35 min", "5 min warmup + 12 sets * 2.5 min")
    }

    func testContentForStrengthDayWithNoSupersetsCountsExercises() {
        let day = ProgramDay(
            weekday: 1, title: nil, focus: "upper",
            exercises: [ProgramExercise(name: "Bench", sets: 3, repsLow: 8)]
        )
        let (title, body) = TrainerSessionReminderScheduler.content(for: day, timeOfDay: (8, 0))
        XCTAssertEqual(title, "Upper at 08:00", "no title -> falls back to the workout type's display name")
        XCTAssertEqual(body, "1 exercise, ~13 min", "5 min warmup + 3 sets * 2.5 min = 12.5, rounds up to 13")
    }

    func testContentForConditioningDayUsesTheTrainersFreeText() {
        let day = ProgramDay(
            weekday: 3, title: nil, focus: "run",
            exercises: [ProgramExercise(name: "Run", sets: 1, repsLow: 1, detail: "50' zone 2")]
        )
        let (title, body) = TrainerSessionReminderScheduler.content(for: day, timeOfDay: (17, 0))
        XCTAssertEqual(title, "Run today")
        XCTAssertEqual(body, "50' zone 2")
    }

    // MARK: - Fixtures

    /// `weekday` in TrainerProgram's Mon=1...Sun=7 convention.
    private func strengthDay(weekday: Int, title: String) -> ProgramDay {
        ProgramDay(
            weekday: weekday, title: title, focus: "push",
            exercises: [
                ProgramExercise(name: "Bench", sets: 3, repsLow: 8, group: 1),
                ProgramExercise(name: "Row", sets: 3, repsLow: 8, group: 1),
            ]
        )
    }

    /// Builds a container, a UserSettings row, and an active TrainerProgram
    /// with ONE session at `today + offsetDays` (never at a fixed weekday —
    /// so the test can't flake depending on which real weekday it runs on).
    /// Returns the target date so the test can assert on it.
    @discardableResult
    private func makeActiveProgramSession(
        in context: ModelContext,
        offsetDays: Int,
        title: String = "Lifting 2"
    ) throws -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let targetDate = try XCTUnwrap(cal.date(byAdding: .day, value: offsetDays, to: today))
        let weekday = TrainerProgram.isoWeekday(of: targetDate)
        let programStart = TrainingCalendar.mondayOfWeek(containing: today)

        context.insert(TrainerProgram(
            name: "PT",
            startDate: programStart,
            weeks: [ProgramWeek(days: [strengthDay(weekday: weekday, title: title)])],
            repeats: true,
            sourceKind: "text"
        ))
        return targetDate
    }

    private func scheduledTrainerReminders(_ mock: MockNotificationService) -> [ScheduledNotification] {
        mock.scheduledNotifications.filter { $0.category.hasPrefix("trainer_session_") }
    }

    // MARK: - End-to-end scheduling

    func testSchedulesOneReminderForTheActiveSession() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        let targetDate = try makeActiveProgramSession(in: context, offsetDays: 2)
        try context.save()

        let mock = MockNotificationService()
        TrainerSessionReminderScheduler.reschedule(
            notifications: mock,
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )

        let reminders = scheduledTrainerReminders(mock)
        XCTAssertEqual(reminders.count, 1)
        let reminder = try XCTUnwrap(reminders.first)
        XCTAssertEqual(reminder.title, "Lifting 2 at 17:00", "no UserDailyPlanProfile -> the anyFree/17:00 fallback")
        XCTAssertTrue(
            Calendar.current.isDate(reminder.triggerDate, inSameDayAs: targetDate),
            "fires on the session's own date"
        )
    }

    func testUsesTheUsersTrainingTimePreference() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        context.insert(UserDailyPlanProfile(trainingTimePreference: .morning))
        try makeActiveProgramSession(in: context, offsetDays: 1)
        try context.save()

        let mock = MockNotificationService()
        TrainerSessionReminderScheduler.reschedule(
            notifications: mock,
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )

        let reminder = try XCTUnwrap(scheduledTrainerReminders(mock).first)
        XCTAssertEqual(reminder.title, "Lifting 2 at 08:00")
    }

    func testNoActiveProgramSchedulesNothing() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        try context.save()

        let mock = MockNotificationService()
        TrainerSessionReminderScheduler.reschedule(
            notifications: mock,
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )

        XCTAssertTrue(scheduledTrainerReminders(mock).isEmpty)
    }

    // MARK: - Recovery/match pauses are excluded

    func testMatchDaySkipsTheReminder() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        let targetDate = try makeActiveProgramSession(in: context, offsetDays: 3)
        context.insert(Match(kickoff: targetDate))
        try context.save()

        let mock = MockNotificationService()
        TrainerSessionReminderScheduler.reschedule(
            notifications: mock,
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )

        XCTAssertTrue(
            scheduledTrainerReminders(mock).isEmpty,
            "a dated match is a fixed commitment — the trainer's session (and its reminder) is paused that day"
        )
    }

    // MARK: - Toggles gate scheduling entirely

    func testDisabledTrainerSessionToggleSchedulesNothing() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let settings = UserSettings()
        settings.trainerSessionReminderEnabled = false
        context.insert(settings)
        try makeActiveProgramSession(in: context, offsetDays: 1)
        try context.save()

        let mock = MockNotificationService()
        TrainerSessionReminderScheduler.reschedule(
            notifications: mock,
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )

        XCTAssertTrue(scheduledTrainerReminders(mock).isEmpty)
    }

    func testDisabledMasterTrainingReminderToggleSchedulesNothing() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let settings = UserSettings()
        settings.trainingReminderEnabled = false
        context.insert(settings)
        try makeActiveProgramSession(in: context, offsetDays: 1)
        try context.save()

        let mock = MockNotificationService()
        TrainerSessionReminderScheduler.reschedule(
            notifications: mock,
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )

        XCTAssertTrue(scheduledTrainerReminders(mock).isEmpty)
    }

    // MARK: - Stable identifiers

    func testIdentifierIsStableAcrossReschedules() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        try makeActiveProgramSession(in: context, offsetDays: 2)
        try context.save()

        let mock = MockNotificationService()
        TrainerSessionReminderScheduler.reschedule(
            notifications: mock,
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )
        let firstCategory = try XCTUnwrap(scheduledTrainerReminders(mock).first?.category)

        // Reschedule again with nothing changed — a full cancel + rebuild,
        // never an incremental diff, so this pins that the rebuilt id is
        // IDENTICAL, not just that something got scheduled again.
        TrainerSessionReminderScheduler.reschedule(
            notifications: mock,
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )
        let reminders = scheduledTrainerReminders(mock)
        XCTAssertEqual(reminders.count, 1, "the stale one was cancelled before the rebuild, not accumulated")
        XCTAssertEqual(reminders.first?.category, firstCategory)
    }

    // MARK: - Fix #6 — sequence mode must resolve the SAME session Today would

    /// Regression for a real bug this fix introduces the risk of: this
    /// scheduler used to re-derive each day's session with
    /// `program.session(on: date)` — a FIXED-weekday-only lookup. Under
    /// sequence mode that disagrees with what `weekSchedule` (Today/
    /// Nutrition's own real week) actually resolved once the athlete falls
    /// behind — here, one stale completed session shifts the cursor so
    /// TODAY plays the SECOND step even though the first step is the one
    /// authored on today's own weekday. The reminder's content must follow
    /// the resolved key, not the naive weekday guess.
    func testSequenceModeReminderContentMatchesTheResolvedSessionNotTheAuthoredWeekday() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayWeekday = TrainerProgram.isoWeekday(of: today)
        let tomorrowWeekday = todayWeekday == 7 ? 1 : todayWeekday + 1

        let program = TrainerProgram(
            name: "PT",
            startDate: TrainingCalendar.mondayOfWeek(containing: today),
            weeks: [ProgramWeek(days: [
                strengthDay(weekday: todayWeekday, title: "Lifting A"),
                ProgramDay(
                    weekday: tomorrowWeekday, title: "Aerobic Run", focus: "run",
                    exercises: [ProgramExercise(name: "Run", sets: 1, repsLow: 1, detail: "30' easy")]
                ),
            ])],
            repeats: true,
            sourceKind: "text",
            scheduleMode: .sequence
        )
        context.insert(program)
        // One session already completed, long before this week — pushes the
        // sequence cursor to step 1 for EVERY week, including this one.
        let stale = try XCTUnwrap(cal.date(byAdding: .day, value: -21, to: today))
        let staleCompleted = WorkoutPlan(date: stale, type: .push, status: .completed)
        staleCompleted.programSessionKey = program.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(staleCompleted)
        try context.save()

        let mock = MockNotificationService()
        TrainerSessionReminderScheduler.reschedule(
            notifications: mock,
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context,
            // Start of today, so today's reminder is still in the future
            // whatever time the suite runs (it failed after 5 pm).
            now: today
        )

        let reminders = scheduledTrainerReminders(mock)
        let todayReminder = try XCTUnwrap(reminders.first { cal.isDate($0.triggerDate, inSameDayAs: today) })
        XCTAssertEqual(
            todayReminder.title, "Aerobic Run today",
            "cursor is at step 1 — today runs the conditioning step, not step 0's own authored weekday"
        )

        let tomorrow = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: today))
        if let tomorrowReminder = reminders.first(where: { cal.isDate($0.triggerDate, inSameDayAs: tomorrow) }) {
            XCTAssertEqual(tomorrowReminder.title, "Lifting A at 17:00", "cursor wraps back to step 0")
        }
    }
}
