//
// TrainerFeedbackMigrationTests.swift
// Tempo
//
// trainer-feedback-tests — every field this build added is optional/
// defaulted so existing saved data (programs, exercise history, planned
// exercises, conditioning results) keeps loading unchanged. Pins that
// contract directly: legacy JSON with no `isTest`/`is_test` key still
// decodes, and every new SwiftData property defaults to its no-op value.
//

@testable import Tempo
import XCTest

final class TrainerFeedbackMigrationTests: XCTestCase {
    // MARK: - Codable structs (ProgramDay / ProgramExercise / changeLog)

    func testProgramDayDecodesWithoutIsTestKey() throws {
        // Shaped exactly like data written before `isTest` existed: every
        // field THAT existed back then, present; `isTest` simply absent
        // (Codable synthesis requires every OTHER non-optional field, even
        // ones with a default value, so this includes `id`/`exercises`).
        let json = """
        { "id": "\(UUID().uuidString)", "weekday": 1, "title": "Push", "focus": "push", "exercises": [], "notes": null }
        """
        let day = try JSONDecoder().decode(ProgramDay.self, from: Data(json.utf8))
        XCTAssertNil(day.isTest, "a program saved before this shipped has no isTest key at all")
    }

    func testProgramExerciseDecodesWithoutIsTestKey() throws {
        let json = """
        { "id": "\(UUID().uuidString)", "name": "Bench Press", "sets": 3, "repsLow": 8 }
        """
        let exercise = try JSONDecoder().decode(ProgramExercise.self, from: Data(json.utf8))
        XCTAssertNil(exercise.isTest)
    }

    func testTrainerProgramChangeLogDefaultsToEmpty() {
        let program = TrainerProgram(
            name: "Block", startDate: Date(),
            weeks: [ProgramWeek(days: [])], sourceKind: "text"
        )
        XCTAssertTrue(program.changeLog.isEmpty, "a program saved before this feature shipped has no change log")
    }

    // MARK: - SwiftData model defaults

    func testPlannedExerciseIsTestExerciseDefaultsFalse() {
        let slot = PlannedExercise(order: 0)
        XCTAssertFalse(slot.isTestExercise)
    }

    func testExerciseHistoryIsTrustedMaxDefaultsFalse() {
        let history = ExerciseHistory(date: Date())
        XCTAssertFalse(history.isTrustedMax)
    }

    func testConditioningBlockResultIsBaselineTestDefaultsFalse() {
        let result = ConditioningBlockResult()
        XCTAssertFalse(result.isBaselineTest)
    }
}
