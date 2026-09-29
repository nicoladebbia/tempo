//
// TrainingViewModelPauseIntegrationTests.swift
// Tempo
//
// Pause/travel-pain feature — cross-surface verification (CLAUDE.md:
// "enumerate every reader ... re-verify EACH reader"). `TrainingPauseSchedule`
// itself is pinned in `TrainingPauseScheduleTests.swift`; this file pins the
// GLUE that makes each real reader honour it:
// - TrainingScheduleProvider (and so Nutrition's WeeklyTrainingSchedule/
//   MealPlanInputsFingerprint, which both consume its [DayTrainingSchedule]).
// - TrainingViewModel.missedFixedSession (MissedTrainerSessionCard).
// - TrainingViewModel.weeklyUploadDue (WeeklyUploadPromptCard).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainingViewModelPauseIntegrationTests: XCTestCase {
    private let cal = TrainingCalendar.iso8601

    private func date(_ string: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)!
    }

    private func date(_ string: String, hour: Int, minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: date(string)) ?? date(string)
    }

    private func day(_ weekday: Int, _ focus: String = "push") -> ProgramDay {
        ProgramDay(
            weekday: weekday, title: "Day \(weekday)", focus: focus,
            exercises: [ProgramExercise(name: "Bench Press", sets: 3, repsLow: 8)]
        )
    }

    /// 2026-09-21 is a Monday.
    private func fixedProgram() -> TrainerProgram {
        TrainerProgram(
            name: "PT", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [day(1), day(2), day(3), day(4), day(5)])],
            sourceKind: "text", scheduleMode: .fixed, createdAt: date("2026-09-21")
        )
    }

    // MARK: - Reader: TrainingScheduleProvider (-> Nutrition)

    func testTrainingScheduleProvider_pausedDayReadsAsRestWithNoTrainerSession() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        context.insert(UserSettings())
        let program = fixedProgram()
        context.insert(program)
        context.insert(TrainingPause(reason: .sick, startDate: date("2026-09-22"), plannedEndDate: date("2026-09-24")))
        try context.save()

        let week = TrainingScheduleProvider.weekSchedule(
            containing: date("2026-09-21"),
            trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService(),
            modelContext: context
        )

        let tuesday = week.first { $0.weekday == 2 }
        XCTAssertEqual(tuesday?.mainType, .rest, "Nutrition must see a rest day, not the trainer's push day")
        XCTAssertFalse(tuesday?.isTrainerSession ?? true)
        XCTAssertNil(tuesday?.programSessionKey)

        // A day OUTSIDE the pause still runs the trainer's program normally.
        let monday = week.first { $0.weekday == 1 }
        XCTAssertTrue(monday?.isTrainerSession ?? false, "Monday is before the pause — unaffected")
    }

    // MARK: - Reader: missedFixedSession (MissedTrainerSessionCard)

    func testMissedFixedSession_noPromptWhileTodayIsPaused() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let program = fixedProgram()
        context.insert(program)
        // A real, otherwise-missable Monday session.
        let mon = WorkoutPlan(date: date("2026-09-21"), type: .push, status: .planned)
        mon.programSessionKey = program.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(mon)
        // Today (Tuesday) is paused.
        context.insert(TrainingPause(reason: .sick, startDate: date("2026-09-22"), plannedEndDate: date("2026-09-24")))
        try context.save()

        let vm = TrainingViewModel(trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService())
        XCTAssertNil(
            vm.missedFixedSession(asOf: date("2026-09-22"), modelContext: context),
            "no missed prompts at all while today is paused"
        )
    }

    func testMissedFixedSession_pastPausedDayIsNotReportedAsMissed() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        // Single-session-day program (Tuesday only) so there's no OTHER
        // real miss (e.g. an untouched Monday) for the search window to
        // legitimately surface instead — this test is specifically about
        // Tuesday itself never counting as missed.
        let program = TrainerProgram(
            name: "PT", startDate: date("2026-09-21"), weeks: [ProgramWeek(days: [day(2)])], sourceKind: "text",
            createdAt: date("2026-09-21")
        )
        context.insert(program)
        // Tuesday's session was never touched — but Tuesday was paused.
        let tue = WorkoutPlan(date: date("2026-09-22"), type: .push, status: .planned)
        tue.programSessionKey = program.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(tue)
        context.insert(TrainingPause(reason: .injured, startDate: date("2026-09-22"), plannedEndDate: date("2026-09-22")))
        try context.save()

        let vm = TrainingViewModel(trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService())
        // Asked on Wednesday (pause already over) — Tuesday must NOT surface
        // as missed, same as a match day wouldn't.
        XCTAssertNil(
            vm.missedFixedSession(asOf: date("2026-09-23"), modelContext: context),
            "a paused day is a deliberate override, not a miss"
        )
    }

    // MARK: - Reader: weeklyUploadDue (WeeklyUploadPromptCard)

    func testWeeklyUploadDue_suppressedWhenPauseCoversTheWholeServedWeek() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let program = TrainerProgram(
            name: "Coach", startDate: date("2026-09-21"), weeks: [ProgramWeek(days: [day(1)])],
            isActive: true, sourceKind: "text", cadence: .weekly
        )
        context.insert(program)
        context.insert(TrainingPause(reason: .sick, startDate: date("2026-09-21"), plannedEndDate: date("2026-09-27")))
        try context.save()

        let vm = TrainingViewModel(trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService())
        XCTAssertNil(
            vm.weeklyUploadDue(modelContext: context, now: date("2026-09-27", hour: 19)),
            "sick the whole week — don't nag for a new program"
        )
    }

    func testWeeklyUploadDue_stillDueWhenPauseOnlyCoversPartOfTheWeek() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let program = TrainerProgram(
            name: "Coach", startDate: date("2026-09-21"), weeks: [ProgramWeek(days: [day(1)])],
            isActive: true, sourceKind: "text", cadence: .weekly
        )
        context.insert(program)
        // Only 2 of the 7 days paused.
        context.insert(TrainingPause(reason: .sick, startDate: date("2026-09-21"), plannedEndDate: date("2026-09-22")))
        try context.save()

        let vm = TrainingViewModel(trainingEngine: MockTrainingEngine(), whoop: MockWhoopService(), healthKit: MockHealthKitService())
        XCTAssertEqual(
            vm.weeklyUploadDue(modelContext: context, now: date("2026-09-27", hour: 19))?.id, program.id,
            "back most of the week — still nag for the new program"
        )
    }
}
