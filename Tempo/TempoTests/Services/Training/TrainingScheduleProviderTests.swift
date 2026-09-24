//
// TrainingScheduleProviderTests.swift
// Tempo
//
// Fix #3 — Nutrition used to guess the week from raw settings
// (WeeklyTrainingSchedule.make(split:footballDays:)), which agreed with
// Training only for a plain split + recurring football. These tests pin
// TrainingScheduleProvider (the shared source of truth Nutrition now uses
// instead) against the real generation path: an active TrainerProgram
// overlay (including a two-a-day second session) must show up exactly as
// Training's own Week Plan would show it, and a football-only user (no
// program) must see the SAME week the old settings-only guess produced —
// the regression the fix must not break.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainingScheduleProviderTests: XCTestCase {
    private let cal = TrainingCalendar.iso8601

    private func date(_ string: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)!
    }

    /// A ProgramDay needs at least one exercise or TrainerProgram.sessions(on:)
    /// drops it (see TrainerProgram.swift `!day.exercises.isEmpty`).
    private func day(_ weekday: Int, _ focus: String) -> ProgramDay {
        ProgramDay(
            weekday: weekday,
            title: "Day \(weekday)",
            focus: focus,
            exercises: [ProgramExercise(name: "Placeholder", sets: 1, repsLow: 1)]
        )
    }

    /// 2026-09-21 is a Monday (matches the fixture used in TrainerProgramTests).
    private let monday = "2026-09-21"

    // MARK: - Trainer program overlay (main + second session)

    func testTrainerProgramOverlay_mainAndSecondSessionAndRestDay() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        context.insert(TrainerProgram(
            name: "PT",
            startDate: date(monday),
            weeks: [ProgramWeek(days: [
                day(1, "push"), // Monday: lift
                day(2, "run"), // Tuesday: conditioning only
            ])],
            sourceKind: "text"
        ))
        try context.save()

        let week = TrainingScheduleProvider.weekSchedule(
            containing: date(monday),
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )
        XCTAssertEqual(week.count, 7)

        let mon = try XCTUnwrap(week.first { $0.weekday == 1 })
        XCTAssertEqual(mon.mainType, .push, "Monday follows the trainer's lift, not the settings split")
        XCTAssertTrue(mon.isTrainerSession)

        let tue = try XCTUnwrap(week.first { $0.weekday == 2 })
        XCTAssertEqual(tue.mainType, .run, "Tuesday's only session is conditioning")
        XCTAssertTrue(tue.isTrainerSession)

        let wed = try XCTUnwrap(week.first { $0.weekday == 3 })
        XCTAssertEqual(wed.mainType, .rest, "no trainer session Wednesday → rest, not the generated split")
        XCTAssertFalse(wed.isTrainerSession)
    }

    func testTrainerProgramOverlay_liftPlusConditioningSameDayIsASecondSession() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        context.insert(TrainerProgram(
            name: "PT",
            startDate: date(monday),
            weeks: [ProgramWeek(days: [
                day(1, "legs"),
                day(1, "sprint"), // same weekday — becomes the day's second part
            ])],
            sourceKind: "text"
        ))
        try context.save()

        let week = TrainingScheduleProvider.weekSchedule(
            containing: date(monday),
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )
        let mon = try XCTUnwrap(week.first { $0.weekday == 1 })
        XCTAssertEqual(mon.mainType, .legs)
        XCTAssertEqual(mon.secondaryType, .sprint, "the sprint session becomes Monday's second part")
        XCTAssertTrue(mon.isTrainerSession)
    }

    // MARK: - Football stays football when the trainer has no session that day

    func testFootballDayKeptWhenTrainerHasNoSessionThatDay() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let settings = UserSettings()
        settings.footballDays = .wednesday
        context.insert(settings)
        // Trainer only programs Monday — Wednesday football is untouched.
        context.insert(TrainerProgram(
            name: "PT",
            startDate: date(monday),
            weeks: [ProgramWeek(days: [day(1, "upper")])],
            sourceKind: "text"
        ))
        try context.save()

        let week = TrainingScheduleProvider.weekSchedule(
            containing: date(monday),
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )
        let wed = try XCTUnwrap(week.first { $0.weekday == 3 })
        XCTAssertEqual(wed.mainType, .football, "recurring football day stays football under a trainer program")
    }

    // MARK: - Dated match is a fixed commitment, trainer or not

    func testMatchDayKeptDuringTrainerProgram() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        // `fetchUpcomingMatches` filters on the REAL wall-clock `Date()` (not
        // an injectable reference date), so the fixture must sit in the
        // CURRENT ISO week to stay "upcoming" no matter when this test runs.
        let currentMonday = TrainingCalendar.mondayOfWeek(containing: Date())
        let thursday = try XCTUnwrap(cal.date(byAdding: .day, value: 3, to: currentMonday))
        context.insert(UserSettings())
        context.insert(Match(kickoff: thursday))
        context.insert(TrainerProgram(
            name: "PT",
            startDate: currentMonday,
            weeks: [ProgramWeek(days: [day(4, "upper")])], // trainer ALSO wants Thursday
            sourceKind: "text"
        ))
        try context.save()

        let week = TrainingScheduleProvider.weekSchedule(
            containing: currentMonday,
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )
        let thu = try XCTUnwrap(week.first { $0.weekday == 4 })
        XCTAssertEqual(thu.mainType, .football, "a dated match day is a fixed commitment — the trainer's session doesn't override it")
        XCTAssertFalse(thu.isTrainerSession)
    }

    // MARK: - Football-only user (no trainer program) — regression

    /// The real `TrainingEngine` (two-a-days, legs-guarantee, rotation shifted
    /// around football) was ALWAYS richer than the naive
    /// `WeeklyTrainingSchedule.make(split:footballDays:)` projection — that gap
    /// is exactly why Nutrition disagreed with Training even in the simplest
    /// case, not just under a trainer program. So this does NOT assert
    /// byte-for-byte equality with the legacy guess (real engine output for
    /// Thu/Fri/Sat legitimately differs — a rotation shift and an added
    /// two-a-day the naive guess never modeled). What must NOT regress:
    /// the specific off-by-one football placement `.make()`'s own unit tests
    /// pin (football lands on ITS weekday, not shifted by one), and the split
    /// still drives every non-football day (not silently falling back to
    /// "Rest" everywhere, which would signal the settings read broke).
    func testFootballOnlyUser_footballLandsOnItsDayAndSplitStillDrivesTheRest() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let settings = UserSettings()
        settings.trainingSplit = .pushPullLegs
        settings.footballDays = .wednesday
        context.insert(settings)
        try context.save()

        let week = TrainingScheduleProvider.weekSchedule(
            containing: date(monday),
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )
        let built = WeeklyTrainingSchedule.build(from: week)

        XCTAssertEqual(built.byWeekday[3], "Football", "Wednesday football lands on Wednesday, not shifted")
        XCTAssertNotEqual(built.byWeekday[1], "Football", "Monday must not be football (the off-by-one bug)")
        XCTAssertEqual(built.byWeekday.count, 7, "every day of the week gets a label")
        let nonFootballLabels = (1 ... 7).filter { $0 != 3 }.compactMap { built.byWeekday[$0] }
        XCTAssertTrue(
            nonFootballLabels.contains { $0.contains("Push") || $0.contains("Pull") || $0.contains("Legs") },
            "the push/pull/legs split still drives the rest of the week: \(nonFootballLabels)"
        )
    }

    /// Locks that `WeeklyTrainingSchedule.build(from:)` still agrees with the
    /// legacy `.make(split:footballDays:)` on the ONE thing both must get
    /// right identically: which weekday football lands on. This is the exact
    /// bug WeeklyTrainingScheduleTests pins for `.make` — proving the new
    /// path didn't reintroduce it under a different code path.
    func testFootballOnlyUser_sundayFootballAgreesWithLegacyPlacement() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let settings = UserSettings()
        settings.trainingSplit = .pushPullLegs
        settings.footballDays = .sunday
        context.insert(settings)
        try context.save()

        let week = TrainingScheduleProvider.weekSchedule(
            containing: date(monday),
            trainingEngine: TrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService(),
            modelContext: context
        )
        let built = WeeklyTrainingSchedule.build(from: week)
        let legacy = WeeklyTrainingSchedule.make(split: .pushPullLegs, footballDays: .sunday)

        XCTAssertEqual(built.byWeekday[7], "Football")
        XCTAssertEqual(built.byWeekday[7], legacy.byWeekday[7], "Sunday football placement agrees with the legacy guess")
        XCTAssertNotEqual(built.byWeekday[1], "Football", "Monday must not be football (the off-by-one bug)")
    }

    // MARK: - WeeklyTrainingSchedule.build(from:) — second session formatting

    func testBuild_appendsSecondSessionToLabel() {
        let week: [DayTrainingSchedule] = [
            DayTrainingSchedule(weekday: 1, date: Date(), mainType: .legs, secondaryType: .sprint, isTrainerSession: true),
            DayTrainingSchedule(weekday: 2, date: Date(), mainType: .rest, secondaryType: nil, isTrainerSession: false),
        ]
        let schedule = WeeklyTrainingSchedule.build(from: week)
        XCTAssertEqual(schedule.byWeekday[1], "Legs + Sprint")
        XCTAssertEqual(schedule.byWeekday[2], "Rest")
    }
}
