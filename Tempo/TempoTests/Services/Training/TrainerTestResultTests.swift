//
// TrainerTestResultTests.swift
// Tempo
//
// trainer-feedback-tests — covers three things together since they share one
// scenario (a logged strength/run TEST):
//   1. `TrainingViewModel.reliableEstimated1RM`'s trusted-max override rule.
//   2. `ConditioningBaselineProvider`'s distance-shape matching.
//   3. `TrainerTestResultMessage`'s copy.
// All dates are injected (`asOf:`/fixture `Date`s) — never `Date()` inside
// the assertions themselves.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class TrainerTestResultTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = TrainingCalendar.iso8601
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    // MARK: - Trusted max outranks a later ordinary estimate

    func testTrustedMaxOutranksALaterLowerOrdinaryEstimate() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let squat = Exercise(
            name: "Barbell Back Squat", muscleGroup: .quads, equipment: .barbell,
            movementPattern: .squat, isCompound: true
        )
        context.insert(squat)
        // A real 5RM test, 30 days ago: e1RM 150.
        context.insert(ExerciseHistory(date: date("2026-08-27"), estimated1RM: 150, isTrustedMax: true, exercise: squat))
        // An ordinary AMRAP set 10 days ago produced a LOWER estimate — not
        // real weakness, just a submax set, and it must not erase the test.
        context.insert(ExerciseHistory(date: date("2026-09-16"), estimated1RM: 130, isTrustedMax: false, exercise: squat))
        try context.save()

        let result = TrainingViewModel.reliableEstimated1RM(for: squat, asOf: date("2026-09-26"))
        XCTAssertEqual(result, 150, "the trusted test's max still wins over a later, lower, untrusted estimate")
    }

    func testLaterHigherEstimateStillWinsOverATrustedMax() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let squat = Exercise(
            name: "Barbell Back Squat", muscleGroup: .quads, equipment: .barbell,
            movementPattern: .squat, isCompound: true
        )
        context.insert(squat)
        context.insert(ExerciseHistory(date: date("2026-08-27"), estimated1RM: 150, isTrustedMax: true, exercise: squat))
        // Real progress since the test — a genuinely bigger later lift.
        context.insert(ExerciseHistory(date: date("2026-09-16"), estimated1RM: 160, isTrustedMax: false, exercise: squat))
        try context.save()

        let result = TrainingViewModel.reliableEstimated1RM(for: squat, asOf: date("2026-09-26"))
        XCTAssertEqual(result, 160, "genuine later progress must still be reflected")
    }

    func testTrustedMaxOutsideItsWindowFallsBackToOrdinaryRule() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let squat = Exercise(
            name: "Barbell Back Squat", muscleGroup: .quads, equipment: .barbell,
            movementPattern: .squat, isCompound: true
        )
        context.insert(squat)
        // 200 days ago — outside the ~180-day trusted window AND the 90-day
        // ordinary window.
        context.insert(ExerciseHistory(date: date("2026-03-10"), estimated1RM: 150, isTrustedMax: true, exercise: squat))
        try context.save()

        XCTAssertNil(TrainingViewModel.reliableEstimated1RM(for: squat, asOf: date("2026-09-26")))
    }

    func testNoTrustedRowFallsBackToMostRecentWithin90Days() throws {
        let container = try TempoModelContainer.create(inMemory: true)
        let context = container.mainContext
        let bench = Exercise(
            name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
            movementPattern: .horizontalPush, isCompound: true
        )
        context.insert(bench)
        context.insert(ExerciseHistory(date: date("2026-09-10"), estimated1RM: 90, isTrustedMax: false, exercise: bench))
        try context.save()

        XCTAssertEqual(TrainingViewModel.reliableEstimated1RM(for: bench, asOf: date("2026-09-26")), 90)
    }

    // MARK: - TrainerTestResultMessage

    func testStrengthTestMessageWithATrainerPercent() {
        let squat = Exercise(
            name: "Squat", muscleGroup: .quads, equipment: .barbell,
            movementPattern: .squat, isCompound: true
        )
        let program = TrainerProgram(
            name: "Block", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [
                ProgramDay(
                    weekday: 3, title: "Legs", focus: "legs",
                    exercises: [ProgramExercise(name: "Squat", exerciseID: squat.id, sets: 3, repsLow: 5, percentOf1RM: 0.75)],
                    notes: nil
                ),
            ])],
            sourceKind: "text"
        )
        let message = TrainerTestResultMessage.strengthTestMessage(
            exercise: squat, newMaxKg: 120, weightUnit: .kg, program: program
        )
        XCTAssertEqual(message, "New max: Squat 120 kg — your trainer's 75% is now 90 kg.")
    }

    func testStrengthTestMessageWithoutAPercentFallsBackToPlainMax() {
        let squat = Exercise(
            name: "Squat", muscleGroup: .quads, equipment: .barbell,
            movementPattern: .squat, isCompound: true
        )
        let message = TrainerTestResultMessage.strengthTestMessage(
            exercise: squat, newMaxKg: 120, weightUnit: .kg, program: nil
        )
        XCTAssertEqual(message, "New max: Squat 120 kg.")
    }

    // MARK: - ConditioningBaselineProvider

    /// "test 30m" — a bare distance with no rep count — parses as
    /// `.distance`, not `.repsDistance`; its logged time lives in
    /// `durationSeconds` (`ConditioningLogSheet`'s "Duration (min)" field).
    func testConditioningBaselineMatchesABareDistanceShape() {
        let program = TrainerProgram(
            name: "Block", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [
                ProgramDay(
                    weekday: 4, title: "Sprints", focus: "sprint",
                    exercises: [
                        ProgramExercise(name: "Test 30m", sets: 1, repsLow: 1, detail: "test 30m", isTest: true),
                        ProgramExercise(name: "30m rep", sets: 1, repsLow: 1, detail: "30m sprint"),
                    ],
                    notes: nil
                ),
            ])],
            sourceKind: "text"
        )
        let key = program.sessionKey(weekIndex: 0, dayIndex: 0)
        let baselineID = program.weeks[0].days[0].exercises[0].id

        let baselineResult = ConditioningBlockResult(
            programSessionKey: key, blockID: baselineID, durationSeconds: 4.3, isBaselineTest: true
        )

        let bestTime = ConditioningBaselineProvider.bestTime(distance: 30, unit: .meters, in: [baselineResult], program: program)
        XCTAssertEqual(bestTime, 4.3)

        let displayLine = ConditioningBaselineProvider.displayLine(
            forDetail: program.weeks[0].days[0].exercises[1].detail, results: [baselineResult], program: program
        )
        XCTAssertEqual(displayLine, "Your best 30m: 4.30″")
    }

    /// "1 rep 30m" — an explicit single-rep count — parses as
    /// `.repsDistance`; its logged time is the best of `repTimesSeconds`
    /// (`ConditioningLogSheet`'s per-rep time grid).
    func testConditioningBaselineMatchesARepsDistanceShape() {
        let program = TrainerProgram(
            name: "Block", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [
                ProgramDay(
                    weekday: 4, title: "Sprints", focus: "sprint",
                    exercises: [ProgramExercise(name: "Test 30m", sets: 1, repsLow: 1, detail: "1 rep 30m", isTest: true)],
                    notes: nil
                ),
            ])],
            sourceKind: "text"
        )
        let key = program.sessionKey(weekIndex: 0, dayIndex: 0)
        let baselineID = program.weeks[0].days[0].exercises[0].id
        let baselineResult = ConditioningBlockResult(
            programSessionKey: key, blockID: baselineID, repTimesSeconds: [4.3, 4.5], isBaselineTest: true
        )

        let bestTime = ConditioningBaselineProvider.bestTime(distance: 30, unit: .meters, in: [baselineResult], program: program)
        XCTAssertEqual(bestTime, 4.3, "the best (lowest) of the logged rep times")
    }

    func testConditioningBaselineIgnoresNonBaselineResults() {
        let program = TrainerProgram(
            name: "Block", startDate: date("2026-09-21"),
            weeks: [ProgramWeek(days: [
                ProgramDay(
                    weekday: 4, title: "Sprints", focus: "sprint",
                    exercises: [ProgramExercise(name: "30m rep", sets: 1, repsLow: 1, detail: "30m sprint")],
                    notes: nil
                ),
            ])],
            sourceKind: "text"
        )
        let key = program.sessionKey(weekIndex: 0, dayIndex: 0)
        let blockID = program.weeks[0].days[0].exercises[0].id
        // Same shape and a real logged time — excluded ONLY because it isn't
        // flagged as a baseline test.
        let ordinary = ConditioningBlockResult(programSessionKey: key, blockID: blockID, durationSeconds: 4.1, isBaselineTest: false)

        XCTAssertNil(ConditioningBaselineProvider.bestTime(distance: 30, unit: .meters, in: [ordinary], program: program))
    }
}
