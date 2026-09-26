//
// WeeklyUploadReminderSchedulerTests.swift
// Tempo
//
// Weekly-upload feature — pins that the Sunday/Monday reminders are only
// scheduled for a `.weekly`-cadence active program, gated by both the global
// and sibling toggles, cancelled/never-rescheduled once the upcoming week is
// covered, and use stable identifiers (a rebuild never accumulates).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WeeklyUploadReminderSchedulerTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        components.calendar = .current
        return components.date!
    }

    private func weeklyProgram(startDate: Date) -> TrainerProgram {
        TrainerProgram(
            name: "Coach", startDate: startDate, weeks: [ProgramWeek(days: [])],
            repeats: true, isActive: true, sourceKind: "text", cadence: .weekly
        )
    }

    private func sundayReminders(_ mock: MockNotificationService) -> [ScheduledNotification] {
        mock.scheduledNotifications.filter { $0.category == MockNotificationService.weeklyUploadSundayCategory }
    }

    private func mondayReminders(_ mock: MockNotificationService) -> [ScheduledNotification] {
        mock.scheduledNotifications.filter { $0.category == MockNotificationService.weeklyUploadMondayCategory }
    }

    private func reschedule(_ mock: MockNotificationService, context: ModelContext, now: Date) {
        WeeklyUploadReminderScheduler.reschedule(
            notifications: mock,
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context,
            now: now
        )
    }

    // MARK: - Happy path

    func testSchedulesBothReminders() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        let program = weeklyProgram(startDate: date(2026, 9, 21))
        context.insert(program)
        try context.save()

        let mock = MockNotificationService()
        reschedule(mock, context: context, now: date(2026, 9, 22))

        XCTAssertEqual(sundayReminders(mock).count, 1)
        XCTAssertEqual(mondayReminders(mock).count, 1)
        XCTAssertEqual(sundayReminders(mock).first?.triggerDate, date(2026, 9, 27, hour: 19))
        XCTAssertEqual(mondayReminders(mock).first?.triggerDate, date(2026, 9, 28, hour: 8))
    }

    func testPastSundayDeadlineOnlySchedulesTheMondayNudge() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        let program = weeklyProgram(startDate: date(2026, 9, 21))
        context.insert(program)
        try context.save()

        let mock = MockNotificationService()
        reschedule(mock, context: context, now: date(2026, 9, 27, hour: 20))

        XCTAssertTrue(sundayReminders(mock).isEmpty, "already past — nothing to schedule in the future")
        XCTAssertEqual(mondayReminders(mock).count, 1)
    }

    // MARK: - Not weekly / no program

    func testBlockCadenceSchedulesNothing() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        let program = TrainerProgram(
            name: "Coach", startDate: date(2026, 9, 21), weeks: [ProgramWeek(days: [])],
            repeats: true, isActive: true, sourceKind: "text", cadence: .block
        )
        context.insert(program)
        try context.save()

        let mock = MockNotificationService()
        reschedule(mock, context: context, now: date(2026, 9, 27, hour: 20))

        XCTAssertTrue(sundayReminders(mock).isEmpty)
        XCTAssertTrue(mondayReminders(mock).isEmpty)
    }

    func testNoActiveProgramSchedulesNothing() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        try context.save()

        let mock = MockNotificationService()
        reschedule(mock, context: context, now: date(2026, 9, 27, hour: 20))

        XCTAssertTrue(sundayReminders(mock).isEmpty)
        XCTAssertTrue(mondayReminders(mock).isEmpty)
    }

    // MARK: - Toggles gate scheduling entirely

    func testDisabledWeeklyUploadToggleSchedulesNothing() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let settings = UserSettings()
        settings.weeklyUploadReminderEnabled = false
        context.insert(settings)
        context.insert(weeklyProgram(startDate: date(2026, 9, 21)))
        try context.save()

        let mock = MockNotificationService()
        reschedule(mock, context: context, now: date(2026, 9, 27, hour: 20))

        XCTAssertTrue(sundayReminders(mock).isEmpty)
        XCTAssertTrue(mondayReminders(mock).isEmpty)
    }

    func testDisabledGlobalTrainingReminderToggleSchedulesNothing() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let settings = UserSettings()
        settings.trainingReminderEnabled = false
        context.insert(settings)
        context.insert(weeklyProgram(startDate: date(2026, 9, 21)))
        try context.save()

        let mock = MockNotificationService()
        reschedule(mock, context: context, now: date(2026, 9, 27, hour: 20))

        XCTAssertTrue(sundayReminders(mock).isEmpty)
        XCTAssertTrue(mondayReminders(mock).isEmpty)
    }

    // MARK: - Regression — keeps nagging every week, not just once

    /// The bug this guards: anchoring the one-shot fire dates to the
    /// program's ORIGINAL served week means that once both guards
    /// (`fireDate > now`) fail after the very first missed cycle, they fail
    /// forever — no reminder ever gets scheduled again, even though the
    /// in-app card keeps showing. `effectiveWeekMonday` rolls the anchor
    /// forward to `now`'s own week so a fresh Sunday/Monday keeps getting
    /// scheduled every week the athlete keeps ignoring it.
    func testStillSchedulesFreshRemindersAfterMultipleMissedWeeks() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        // Served week 2026-09-21 — three weeks stale relative to `now` below.
        context.insert(weeklyProgram(startDate: date(2026, 9, 21)))
        try context.save()

        let mock = MockNotificationService()
        // Tuesday of the week starting 2026-10-12 — well past the original
        // served week's own (long-expired) Sunday/Monday deadlines.
        reschedule(mock, context: context, now: date(2026, 10, 13))

        let sunday = try XCTUnwrap(sundayReminders(mock).first)
        let monday = try XCTUnwrap(mondayReminders(mock).first)
        XCTAssertEqual(sunday.triggerDate, date(2026, 10, 18, hour: 19), "this week's own Sunday, not the original served week's")
        XCTAssertEqual(monday.triggerDate, date(2026, 10, 19, hour: 8))
        XCTAssertGreaterThan(sunday.triggerDate, date(2026, 10, 13), "both fire dates are still in the future")
        XCTAssertGreaterThan(monday.triggerDate, date(2026, 10, 13))
    }

    // MARK: - Cancelled once the upcoming week is covered

    func testUpcomingWeekAlreadyCoveredCancelsBoth() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        let active = weeklyProgram(startDate: date(2026, 9, 21))
        context.insert(active)
        let queued = TrainerProgram(
            name: "Coach", startDate: date(2026, 9, 28), weeks: [ProgramWeek(days: [])],
            isActive: false, sourceKind: "text", queuedActivationDate: date(2026, 9, 28), cadence: .weekly
        )
        context.insert(queued)
        try context.save()

        let mock = MockNotificationService()
        reschedule(mock, context: context, now: date(2026, 9, 27, hour: 20))

        XCTAssertTrue(sundayReminders(mock).isEmpty)
        XCTAssertTrue(mondayReminders(mock).isEmpty)
    }

    // MARK: - Stable identifiers — a rebuild never accumulates

    func testRescheduleNeverAccumulates() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        context.insert(weeklyProgram(startDate: date(2026, 9, 21)))
        try context.save()

        let mock = MockNotificationService()
        reschedule(mock, context: context, now: date(2026, 9, 22))
        reschedule(mock, context: context, now: date(2026, 9, 22))

        XCTAssertEqual(sundayReminders(mock).count, 1)
        XCTAssertEqual(mondayReminders(mock).count, 1)
    }
}
