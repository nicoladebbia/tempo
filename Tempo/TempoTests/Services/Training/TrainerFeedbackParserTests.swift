//
// TrainerFeedbackParserTests.swift
// Tempo
//
// trainer-feedback-tests — pins the JSON contract between the Sonnet proxy's
// reply and `[RawTrainerFeedbackEdit]`. Pure parsing only, fixture JSON —
// never calls the real AI.
//

@testable import Tempo
import XCTest

final class TrainerFeedbackParserTests: XCTestCase {
    func testParsesUpdateExerciseWithWeightDelta() throws {
        let json = """
        { "edits": [
            { "type": "update_exercise", "weekday": null, "exercise_name": "RDL", "weight_delta_kg": 5 }
        ]}
        """
        let edits = try TrainerFeedbackParser.parse(json)
        XCTAssertEqual(edits.count, 1)
        XCTAssertEqual(edits[0].type, .updateExercise)
        XCTAssertEqual(edits[0].exerciseName, "RDL")
        XCTAssertEqual(edits[0].weightDeltaKg, 5)
        XCTAssertNil(edits[0].weekday)
    }

    func testParsesSkipSessionWithReason() throws {
        let json = """
        { "edits": [
            { "type": "skip_session", "weekday": 4, "exercise_name": "sprints", "reason": "knee" }
        ]}
        """
        let edits = try TrainerFeedbackParser.parse(json)
        XCTAssertEqual(edits[0].type, .skipSession)
        XCTAssertEqual(edits[0].weekday, 4)
        XCTAssertEqual(edits[0].reason, "knee")
    }

    func testParsesMoveDay() throws {
        let json = """
        { "edits": [
            { "type": "move_day", "weekday": 3, "move_to_weekday": 5 }
        ]}
        """
        let edits = try TrainerFeedbackParser.parse(json)
        XCTAssertEqual(edits[0].type, .moveDay)
        XCTAssertEqual(edits[0].weekday, 3)
        XCTAssertEqual(edits[0].moveToWeekday, 5)
    }

    func testParsesUpdateExerciseWithSets() throws {
        let json = """
        { "edits": [
            { "type": "update_exercise", "weekday": 3, "exercise_name": "squat", "sets": 4 }
        ]}
        """
        let edits = try TrainerFeedbackParser.parse(json)
        XCTAssertEqual(edits[0].weekday, 3)
        XCTAssertEqual(edits[0].sets, 4)
    }

    func testStripsMarkdownFences() throws {
        let json = """
        ```json
        { "edits": [ { "type": "remove_exercise", "exercise_name": "Leg Press" } ] }
        ```
        """
        let edits = try TrainerFeedbackParser.parse(json)
        XCTAssertEqual(edits[0].type, .removeExercise)
        XCTAssertEqual(edits[0].exerciseName, "Leg Press")
    }

    func testEmptyEditsThrowsNoEdits() {
        XCTAssertThrowsError(try TrainerFeedbackParser.parse(#"{ "edits": [] }"#)) { error in
            XCTAssertEqual(error as? TrainerFeedbackParser.ParseError, .noEdits)
        }
    }

    func testMalformedJSONThrowsInvalidJSON() {
        XCTAssertThrowsError(try TrainerFeedbackParser.parse("not json at all")) { error in
            XCTAssertEqual(error as? TrainerFeedbackParser.ParseError, .invalidJSON)
        }
    }

    func testAddExerciseParsesFullPrescription() throws {
        let json = """
        { "edits": [
            { "type": "add_exercise", "weekday": 2, "exercise_name": "Nordic Curl", "sets": 3, "reps_low": 6, "notes": "slow eccentric" }
        ]}
        """
        let edits = try TrainerFeedbackParser.parse(json)
        XCTAssertEqual(edits[0].type, .addExercise)
        XCTAssertEqual(edits[0].sets, 3)
        XCTAssertEqual(edits[0].repsLow, 6)
        XCTAssertEqual(edits[0].notes, "slow eccentric")
    }
}
