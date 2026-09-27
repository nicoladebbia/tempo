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
        guard case let .replaceExercise(weekIndex, dayIndex, exerciseIndex, updated) = resolved[0].action else {
            return XCTFail("expected replaceExercise")
        }
        XCTAssertEqual(weekIndex, 0)
        XCTAssertEqual(dayIndex, 0)
        XCTAssertEqual(exerciseIndex, 0)
        XCTAssertEqual(updated.weightKg, 65)
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
        XCTAssertEqual(resolved[0].summary, "Mon Lower: skipped — knee")
        guard case let .skipDay(_, dayIndex) = resolved[0].action else {
            return XCTFail("expected skipDay")
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
        XCTAssertEqual(resolved[0].summary, "Thu Anaerobic Run: skipped — knee")
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
            weeks: [week], weekIndex: 0
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
}
