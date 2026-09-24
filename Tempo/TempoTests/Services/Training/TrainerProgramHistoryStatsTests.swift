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
        let unrelated = WorkoutPlan(date: date("2026-08-05"), type: .push, status: .completed)
        unrelated.programSessionKey = otherProgram.sessionKey(weekIndex: 0, dayIndex: 0)
        for plan in [done1, done2, missed, secondaryDone, unrelated] {
            context.insert(plan)
        }
        try context.save()

        let stats = TrainerProgramHistoryStats.stats(for: program, modelContext: context)

        XCTAssertEqual(stats.scheduled, 4, "4 rows tagged to THIS program (main or secondary key), unrelated row excluded")
        XCTAssertEqual(stats.done, 3, "done1 + done2 + secondaryDone")
        XCTAssertEqual(stats.fraction, 0.75, accuracy: 0.001)
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
}
