//
// TrainerProgramHistoryStatsTests.swift
// Tempo
//
// Fix #11(c) — basic completion stats for a program's history entry:
// "scheduled" is every WorkoutPlan row Tempo ever tagged to it, "done" is
// how many of those got completed. Rows tagged to a DIFFERENT program must
// never leak into either count.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainerProgramHistoryStatsTests: XCTestCase {
    private func date(_ string: String) -> Date {
        let f = DateFormatter()
        f.calendar = TrainingCalendar.iso8601
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)!
    }

    func testCountsCompletedVsAllTaggedRowsIgnoringOtherPrograms() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let program = TrainerProgram(
            name: "Archived PT", startDate: date("2026-08-01"),
            weeks: [ProgramWeek(days: [ProgramDay(weekday: 1, title: nil, focus: "push", exercises: [
                ProgramExercise(name: "Bench", sets: 3, repsLow: 5),
            ])])],
            isActive: false, sourceKind: "text"
        )
        context.insert(program)
        let otherProgram = TrainerProgram(
            name: "Other", startDate: date("2026-08-01"),
            weeks: [ProgramWeek(days: [])], isActive: false, sourceKind: "text"
        )
        context.insert(otherProgram)

        let key = program.sessionKey(weekIndex: 0, dayIndex: 0)
        let done1 = WorkoutPlan(date: date("2026-08-03"), type: .push, status: .completed)
        done1.programSessionKey = key
        let done2 = WorkoutPlan(date: date("2026-08-10"), type: .push, status: .completed)
        done2.programSessionKey = key
        let missed = WorkoutPlan(date: date("2026-08-17"), type: .push, status: .planned)
        missed.programSessionKey = key
        let secondaryDone = WorkoutPlan(date: date("2026-08-24"), type: .push, status: .completed)
        secondaryDone.programSecondaryKey = key
        secondaryDone.secondaryCompleted = true
        let unrelated = WorkoutPlan(date: date("2026-08-05"), type: .push, status: .completed)
        unrelated.programSessionKey = otherProgram.sessionKey(weekIndex: 0, dayIndex: 0)
        for plan in [done1, done2, missed, secondaryDone, unrelated] {
            context.insert(plan)
        }
        try context.save()

        let stats = TrainerProgramHistoryStats.stats(for: program, modelContext: context)

        XCTAssertEqual(stats.scheduled, 5, "5 Mondays from the program start through its last logged plan, unrelated row excluded")
        XCTAssertEqual(stats.done, 3, "done1 + done2 + secondaryDone")
        XCTAssertEqual(stats.fraction, 0.6, accuracy: 0.001)
    }

    func testZeroScheduledDoesNotDivideByZero() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let program = TrainerProgram(
            name: "Never Run", startDate: date("2026-08-01"),
            weeks: [ProgramWeek(days: [])], isActive: false, sourceKind: "text"
        )
        context.insert(program)
        try context.save()

        let stats = TrainerProgramHistoryStats.stats(for: program, modelContext: context)
        XCTAssertEqual(stats.scheduled, 0)
        XCTAssertEqual(stats.done, 0)
        XCTAssertEqual(stats.fraction, 0)
    }

    // MARK: - Compliance = done / scheduled to date

    private func activeProgram(_ context: ModelContext) -> TrainerProgram {
        let program = TrainerProgram(
            name: "Active PT", startDate: date("2026-09-14"),
            weeks: [ProgramWeek(days: [ProgramDay(weekday: 1, title: nil, focus: "push", exercises: [
                ProgramExercise(name: "Bench", sets: 3, repsLow: 5),
            ])])],
            isActive: true, sourceKind: "text"
        )
        context.insert(program)
        return program
    }

    private func plan(_ context: ModelContext, _ program: TrainerProgram, _ day: String, status: WorkoutStatus) -> WorkoutPlan {
        let plan = WorkoutPlan(date: date(day), type: .push, status: status)
        plan.programSessionKey = program.sessionKey(weekIndex: 0, dayIndex: 0)
        context.insert(plan)
        return plan
    }

    /// Weeks you never opened still count as scheduled (and missed) for the
    /// ACTIVE program; an opened-but-untrained plan is not "done".
    func testActiveProgramCountsUnopenedWeeksAndIgnoresOpenedButUntrainedDays() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let program = activeProgram(context)
        let plans = [
            plan(context, program, "2026-09-14", status: .completed),
            plan(context, program, "2026-09-28", status: .planned), // opened, never trained
        ]
        // Today = Wed 2026-09-30: Mondays 09-14, 09-21, 09-28 are scheduled.
        let stats = TrainerProgramHistoryStats.stats(for: program, plans: plans, today: date("2026-09-30"))
        XCTAssertEqual(stats.scheduled, 3)
        XCTAssertEqual(stats.done, 1)
        XCTAssertEqual(stats.fraction, 1.0 / 3.0, accuracy: 0.001)
    }

    func testTodaysSessionOnlyCountsOnceItIsDone() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let program = activeProgram(context)
        let monday = "2026-09-21"
        let notYet = TrainerProgramHistoryStats.stats(for: program, plans: [], today: date(monday))
        XCTAssertEqual(notYet.scheduled, 1, "only 09-14 is due; today's Monday isn't missed until the day is over")

        let doneToday = plan(context, program, monday, status: .completed)
        let after = TrainerProgramHistoryStats.stats(for: program, plans: [doneToday], today: date(monday))
        XCTAssertEqual(after.scheduled, 2)
        XCTAssertEqual(after.done, 1)
    }

    func testDatedSkipIsNotScheduled() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let program = activeProgram(context)
        program.skippedSessions = [TrainerProgramSkip(
            date: date("2026-09-21"), sessionKey: program.sessionKey(weekIndex: 0, dayIndex: 0), summary: "skip"
        )]
        let stats = TrainerProgramHistoryStats.stats(for: program, plans: [], today: date("2026-09-30"))
        XCTAssertEqual(stats.scheduled, 2, "09-14 and 09-28; the skipped 09-21 isn't scheduled")
    }

    // MARK: - Same exclusions as the missed-session rule

    func testPausedMatchAndRedRecoveryDaysAreNotMissed() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let program = activeProgram(context)
        // Today = Wed 09-30: Mondays 09-14, 09-21, 09-28 are scheduled.
        let pause = TrainingPause(reason: .sick, startDate: date("2026-09-21"), plannedEndDate: date("2026-09-22"))
        let benched = WorkoutPlan(date: date("2026-09-28"), type: .mobility, status: .planned)
        benched.recoveryAdjustment = 0
        context.insert(benched)
        let withPause = TrainerProgramHistoryStats.stats(
            for: program, plans: [benched], today: date("2026-09-30"),
            overrides: TrainerScheduleOverrides(pauses: [pause], matchDays: [])
        )
        XCTAssertEqual(withPause.scheduled, 1, "only 09-14 counts: 09-21 is paused, 09-28 was benched by red recovery")

        let withMatch = TrainerProgramHistoryStats.stats(
            for: program, plans: [], today: date("2026-09-30"),
            overrides: TrainerScheduleOverrides(pauses: [], matchDays: [date("2026-09-14")])
        )
        XCTAssertEqual(withMatch.scheduled, 2, "a match day replaced the session: not a miss")
    }

    /// Sample-program QA: the active card said "0 / 3" on Thursday, and after
    /// Pause the history row said "0 / 1" (no plans → it stopped at week start).
    func testPausedProgramUsesSameDenominatorAsActiveCard() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let days = [1, 2, 3, 4, 6].map {
            ProgramDay(weekday: $0, title: nil, focus: "push", exercises: [ProgramExercise(name: "Bench", sets: 3, repsLow: 5)])
        }
        let program = TrainerProgram(
            name: "Sample", startDate: date("2026-09-28"),
            weeks: [ProgramWeek(days: days)], isActive: true, sourceKind: "text"
        )
        context.insert(program)
        let thursday = date("2026-10-01").addingTimeInterval(10 * 3600)

        let active = TrainerProgramHistoryStats.stats(for: program, plans: [], today: thursday)
        XCTAssertEqual(active, TrainerProgramHistoryStats.Stats(done: 0, scheduled: 3))

        program.isActive = false
        program.endedAt = thursday
        let paused = TrainerProgramHistoryStats.stats(for: program, plans: [], today: thursday)
        XCTAssertEqual(paused, active)
    }
}
