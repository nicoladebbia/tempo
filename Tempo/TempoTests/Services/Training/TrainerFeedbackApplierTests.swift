//
// TrainerFeedbackApplierTests.swift
// Tempo
//
// trainer-feedback-tests — pins how a raw AI edit resolves against a
// CURRENT program week: matched/unmatched, the generated diff summary, and
// `apply(_:acceptedIDs:to:)`'s actual mutation. Pure, no network.
//

@testable import Tempo
import XCTest

final class TrainerFeedbackApplierTests: XCTestCase {
    // MARK: - Fixture

    /// Mon: RDL 3x8 @ 60kg. Wed: Squat 3x5. Thu: two sessions sharing a
    /// weekday — a lift (Bench) and a conditioning block (Sprints) — the
    /// "two sessions same day" ambiguity case.
    private func fixtureWeek() -> ProgramWeek {
        ProgramWeek(days: [
            ProgramDay(
                weekday: 1, title: "Lower", focus: "legs",
                exercises: [ProgramExercise(name: "RDL", sets: 3, repsLow: 8, weightKg: 60)],
                notes: nil
            ),
            ProgramDay(
                weekday: 3, title: "Squat Day", focus: "legs",
                exercises: [ProgramExercise(name: "Squat", sets: 3, repsLow: 5)],
                notes: nil
            ),
            ProgramDay(
                weekday: 4, title: "Upper", focus: "push",
                exercises: [ProgramExercise(name: "Bench Press", sets: 3, repsLow: 8)],
                notes: nil
            ),
            ProgramDay(
                weekday: 4, title: "Anaerobic Run", focus: "sprint",
                exercises: [ProgramExercise(name: "Sprints", sets: 1, repsLow: 1, detail: "4 x 30m")],
                notes: nil
            ),
        ])
    }

    private func edit(
        type: RawTrainerFeedbackEdit.Kind,
        weekday: Int? = nil,
        exerciseName: String? = nil,
        sets: Int? = nil,
        repsLow: Int? = nil,
        weightKg: Double? = nil,
        weightDeltaKg: Double? = nil,
        moveToWeekday: Int? = nil,
        reason: String? = nil
    ) -> RawTrainerFeedbackEdit {
        RawTrainerFeedbackEdit(
            type: type, weekday: weekday, exerciseName: exerciseName, sets: sets, repsLow: repsLow,
            repsHigh: nil, weightKg: weightKg, weightDeltaKg: weightDeltaKg, restSeconds: nil, notes: nil,
            moveToWeekday: moveToWeekday, reason: reason
        )
    }

    // MARK: - update_exercise

    func testWeightDeltaMatchesByNameAloneAndBuildsADiffLine() {
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .updateExercise, exerciseName: "RDL", weightDeltaKg: 5)],
            weeks: [fixtureWeek()], weekIndex: 0
        )
        XCTAssertEqual(resolved.count, 1)
        XCTAssertTrue(resolved[0].matched)
        XCTAssertEqual(resolved[0].summary, "RDL: 60 kg → 65 kg")
        guard case let .replaceExercise(weekIndex, dayIndex, _, changes) = resolved[0].action else {
            return XCTFail("expected replaceExercise")
        }
        XCTAssertEqual(weekIndex, 0)
        XCTAssertEqual(dayIndex, 0)
                XCTAssertEqual(changes.weightDeltaKg, 5)
    }

    func testWeekdayPlusExerciseNameNarrowsToOneDay() {
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .updateExercise, weekday: 3, exerciseName: "squat", sets: 4)],
            weeks: [fixtureWeek()], weekIndex: 0
        )
        XCTAssertTrue(resolved[0].matched)
        XCTAssertEqual(resolved[0].summary, "Squat: 3 sets → 4 sets")
    }

    func testUnknownExerciseNameIsUnmatched() {
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .updateExercise, exerciseName: "Leg Curl", sets: 4)],
            weeks: [fixtureWeek()], weekIndex: 0
        )
        XCTAssertFalse(resolved[0].matched)
        XCTAssertNotNil(resolved[0].matchFailureReason)
    }

    func testRemoveExercise() {
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .removeExercise, exerciseName: "RDL")],
            weeks: [fixtureWeek()], weekIndex: 0
        )
        XCTAssertEqual(resolved[0].summary, "RDL: removed")
        guard case .removeExercise = resolved[0].action else {
            return XCTFail("expected removeExercise")
        }
    }

    // MARK: - skip_session / move_day

    func testSkipSessionWithReason() {
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .skipSession, weekday: 1, reason: "knee")],
            weeks: [fixtureWeek()], weekIndex: 0
        )
        XCTAssertEqual(resolved[0].summary, "Mon Lower: skipped this Mon — knee")
        guard case let .skipDate(_, dayIndex, _) = resolved[0].action else {
            return XCTFail("expected skipDate (fixed mode skips only that date)")
        }
        XCTAssertEqual(dayIndex, 0)
    }

    func testSkipSessionOnAmbiguousWeekdayIsUnmatchedWithoutAHint() {
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .skipSession, weekday: 4)],
            weeks: [fixtureWeek()], weekIndex: 0
        )
        XCTAssertFalse(resolved[0].matched, "two sessions share Thursday — no exercise hint to disambiguate")
    }

    func testSkipSessionOnAmbiguousWeekdayResolvesWithAnExerciseHint() {
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .skipSession, weekday: 4, exerciseName: "sprints", reason: "knee")],
            weeks: [fixtureWeek()], weekIndex: 0
        )
        XCTAssertTrue(resolved[0].matched)
        XCTAssertEqual(resolved[0].summary, "Thu Anaerobic Run: skipped this Thu — knee")
    }

    func testMoveDay() {
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .moveDay, weekday: 3, moveToWeekday: 5)],
            weeks: [fixtureWeek()], weekIndex: 0
        )
        XCTAssertTrue(resolved[0].matched)
        guard case let .moveDay(_, _, newWeekday) = resolved[0].action else {
            return XCTFail("expected moveDay")
        }
        XCTAssertEqual(newWeekday, 5)
    }

    func testNoCurrentWeekIsUnmatched() {
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .updateExercise, exerciseName: "RDL", weightDeltaKg: 5)],
            weeks: [fixtureWeek()], weekIndex: 5
        )
        XCTAssertFalse(resolved[0].matched)
    }

    // MARK: - apply(_:acceptedIDs:to:)

    func testApplyOnlyMutatesAcceptedEdits() {
        let week = fixtureWeek()
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [
                edit(type: .updateExercise, exerciseName: "RDL", weightDeltaKg: 5),
                edit(type: .updateExercise, exerciseName: "Squat", sets: 4),
            ],
            weeks: [week], weekIndex: 0
        )
        let acceptedIDs: Set<UUID> = [resolved[0].id] // only the RDL edit
        let result = TrainerFeedbackApplier.apply(resolved, acceptedIDs: acceptedIDs, to: [week])

        XCTAssertEqual(result[0].days[0].exercises[0].weightKg, 65, "accepted edit applied")
        XCTAssertEqual(result[0].days[1].exercises[0].sets, 3, "rejected edit left untouched")
    }

    func testApplySkipDayEmptiesExercisesSoItNoLongerSchedules() {
        let week = fixtureWeek()
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .skipSession, weekday: 1)],
            weeks: [week], weekIndex: 0, scheduleMode: .sequence
        )
        let result = TrainerFeedbackApplier.apply(resolved, acceptedIDs: Set(resolved.map(\.id)), to: [week])
        let mondayDay = result[0].days[0]
        XCTAssertTrue(mondayDay.exercises.isEmpty)

        // Confirms the "no separate skipped flag needed" claim: an empty day
        // is already invisible to the program's own scheduling.
        let program = TrainerProgram(
            name: "Test", startDate: TrainingCalendar.mondayOfWeek(containing: Date()),
            weeks: result, sourceKind: "text"
        )
        XCTAssertTrue(program.sessions(on: program.startDate).isEmpty)
    }

    // MARK: - Same exercise twice / removals / refusals / dated skips

    private func exerciseNames(_ weeks: [ProgramWeek], day: Int) -> [String] {
        weeks[0].days[day].exercises.map(\.name)
    }

    func testTwoEditsToTheSameExerciseBothStick() {
        let week = fixtureWeek()
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [
                edit(type: .updateExercise, exerciseName: "RDL", sets: 4),
                edit(type: .updateExercise, exerciseName: "RDL", weightDeltaKg: 5),
            ],
            weeks: [week], weekIndex: 0
        )
        let result = TrainerFeedbackApplier.apply(resolved, acceptedIDs: Set(resolved.map(\.id)), to: [week])
        XCTAssertEqual(result[0].days[0].exercises[0].sets, 4)
        XCTAssertEqual(result[0].days[0].exercises[0].weightKg, 65)
    }

    func testTwoWeightDeltasOnTheSameExerciseAddUp() {
        let week = fixtureWeek()
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [
                edit(type: .updateExercise, exerciseName: "RDL", weightDeltaKg: 5),
                edit(type: .updateExercise, exerciseName: "RDL", weightDeltaKg: 2.5),
            ],
            weeks: [week], weekIndex: 0
        )
        XCTAssertEqual(resolved[1].summary, "RDL: 65 kg → 67.5 kg")
        let result = TrainerFeedbackApplier.apply(resolved, acceptedIDs: Set(resolved.map(\.id)), to: [week])
        XCTAssertEqual(result[0].days[0].exercises[0].weightKg, 67.5)
    }

    func testRemovingTwoExercisesOnOneDayRemovesTheRightOnes() {
        let week = ProgramWeek(days: [ProgramDay(
            weekday: 1, title: "Legs", focus: "legs",
            exercises: [
                ProgramExercise(name: "Squat", sets: 3, repsLow: 5),
                ProgramExercise(name: "Leg Press", sets: 3, repsLow: 10),
                ProgramExercise(name: "RDL", sets: 3, repsLow: 8),
                ProgramExercise(name: "Calf Raise", sets: 3, repsLow: 12),
            ],
            notes: nil
        )])
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .removeExercise, exerciseName: "Leg Press"), edit(type: .removeExercise, exerciseName: "Calf Raise")],
            weeks: [week], weekIndex: 0
        )
        let result = TrainerFeedbackApplier.apply(resolved, acceptedIDs: Set(resolved.map(\.id)), to: [week])
        XCTAssertEqual(exerciseNames(result, day: 0), ["Squat", "RDL"])

        // Rejecting the FIRST removal must not shift the second onto the wrong row.
        let onlySecond = TrainerFeedbackApplier.apply(resolved, acceptedIDs: [resolved[1].id], to: [week])
        XCTAssertEqual(exerciseNames(onlySecond, day: 0), ["Squat", "Leg Press", "RDL"])
    }

    func testPlusKgOnALiftWithNoFixedWeightIsRefused() {
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .updateExercise, exerciseName: "Squat", weightDeltaKg: 5)],
            weeks: [fixtureWeek()], weekIndex: 0
        )
        XCTAssertFalse(resolved[0].matched)
        XCTAssertTrue(resolved[0].matchFailureReason?.contains("no fixed weight") == true, resolved[0].matchFailureReason ?? "")
        XCTAssertNil(resolved[0].action)
    }

    func testRefusedDeltaStillAppliesTheRestOfTheEdit() {
        let week = fixtureWeek()
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .updateExercise, exerciseName: "Squat", sets: 5, weightDeltaKg: 5)],
            weeks: [week], weekIndex: 0
        )
        XCTAssertEqual(resolved.count, 2)
        XCTAssertTrue(resolved[0].matched)
        XCTAssertEqual(resolved[0].summary, "Squat: 3 sets → 5 sets")
        XCTAssertFalse(resolved[1].matched)
        let result = TrainerFeedbackApplier.apply(resolved, acceptedIDs: Set(resolved.map(\.id)), to: [week])
        XCTAssertEqual(result[0].days[1].exercises[0].sets, 5)
        XCTAssertNil(result[0].days[1].exercises[0].weightKg)
    }

    func testAbsoluteWeightOnALiftWithNoFixedWeightStillApplies() {
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .updateExercise, exerciseName: "Squat", weightKg: 100)],
            weeks: [fixtureWeek()], weekIndex: 0
        )
        XCTAssertTrue(resolved[0].matched)
    }

    func testFixedModeSkipIsADatedSkipThatLeavesTheProgramAlone() throws {
        let week = fixtureWeek()
        // Wed 2026-09-23 is in the week of Mon 2026-09-21.
        let reference = TrainingCalendar.iso8601.date(from: DateComponents(year: 2026, month: 9, day: 23))!
        let monday = TrainingCalendar.mondayOfWeek(containing: reference)
        let resolved = TrainerFeedbackApplier.resolve(
            edits: [edit(type: .skipSession, weekday: 1, reason: "knee")],
            weeks: [week], weekIndex: 0, scheduleMode: .fixed, referenceDate: reference
        )
        guard case let .skipDate(_, _, date)? = resolved[0].action else {
            return XCTFail("expected skipDate")
        }
        XCTAssertEqual(date, monday)
        let result = TrainerFeedbackApplier.apply(resolved, acceptedIDs: Set(resolved.map(\.id)), to: [week])
        XCTAssertEqual(result[0].days[0].exercises.count, 1, "program weeks untouched")

        let program = TrainerProgram(name: "T", startDate: monday, weeks: [week], sourceKind: "text")
        program.skippedSessions = TrainerFeedbackApplier.skippedSessions(resolved, acceptedIDs: Set(resolved.map(\.id)), program: program)
        XCTAssertEqual(program.skippedSessions.count, 1)
        XCTAssertTrue(program.sessions(on: monday).isEmpty, "that Monday is skipped")
        let nextMonday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: monday))
        XCTAssertEqual(program.sessions(on: nextMonday).count, 1, "the repeating program is back next week")
    }
}
