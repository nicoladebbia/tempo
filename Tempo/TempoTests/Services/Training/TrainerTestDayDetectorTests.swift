//
// TrainerTestDayDetectorTests.swift
// Tempo
//
// trainer-feedback-tests — pins `TrainerTestDayDetector`'s keyword list
// (IT/EN) and confirms it stays conservative (no false positives on ordinary
// program text).
//

@testable import Tempo
import XCTest

final class TrainerTestDayDetectorTests: XCTestCase {
    // MARK: - Positive matches (English)

    func testDetectsExplicitTestWord() {
        XCTAssertTrue(TrainerTestDayDetector.isTestDay(title: "Test 1RM", notes: nil))
    }

    func testDetectsRepMaxShorthand() {
        XCTAssertTrue(TrainerTestDayDetector.isTestExercise(name: "5RM Squat", detail: nil, notes: nil))
        XCTAssertTrue(TrainerTestDayDetector.isTestExercise(name: "Bench", detail: "work up to a 3 RM", notes: nil))
    }

    func testDetectsMaxTestPhrase() {
        XCTAssertTrue(TrainerTestDayDetector.isTestDay(title: "Max Test Week", notes: nil))
    }

    func testDetectsTimeTrial() {
        XCTAssertTrue(TrainerTestDayDetector.isTestExercise(name: "1km", detail: "time trial", notes: nil))
    }

    func testDetectsTest30m() {
        XCTAssertTrue(TrainerTestDayDetector.isTestExercise(name: "Test 30m", detail: nil, notes: nil))
    }

    func testDetectsYoYo() {
        XCTAssertTrue(TrainerTestDayDetector.isTestExercise(name: "Yo-Yo", detail: nil, notes: nil))
        XCTAssertTrue(TrainerTestDayDetector.isTestExercise(name: "Yoyo test", detail: nil, notes: nil))
    }

    // MARK: - Positive matches (Italian)

    func testDetectsItalianMassimale() {
        XCTAssertTrue(TrainerTestDayDetector.isTestDay(title: "Settimana dei massimali", notes: nil))
    }

    func testDetectsItalianCronometrata() {
        XCTAssertTrue(TrainerTestDayDetector.isTestExercise(name: "Corsa", detail: "prova cronometrata", notes: nil))
    }

    // MARK: - Negative (no false positives)

    func testOrdinaryProgramTextIsNotATest() {
        XCTAssertFalse(TrainerTestDayDetector.isTestDay(title: "Hypertrophy Lifting 1", notes: "Follow the order"))
        XCTAssertFalse(TrainerTestDayDetector.isTestExercise(name: "Leg Press", detail: nil, notes: "3x10 @ 70%"))
    }

    func testEmptyTextIsNotATest() {
        XCTAssertFalse(TrainerTestDayDetector.isTestDay(title: nil, notes: nil))
        XCTAssertFalse(TrainerTestDayDetector.isTestExercise(name: nil, detail: nil, notes: nil))
    }

    // MARK: - Wired into the parser

    func testParserFlagsATestDayAndInheritsOntoEveryExercise() throws {
        let json = """
        {
          "name": "Test Week",
          "weeks": [
            {
              "days": [
                {
                  "weekday": 1,
                  "title": "Test 1RM Day",
                  "focus": "full_body",
                  "notes": null,
                  "exercises": [
                    { "name": "Squat", "sets": 1, "reps_low": 1, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null }
                  ]
                }
              ]
            }
          ]
        }
        """
        let parsed = try TrainerProgramParser.parse(json)
        let day = try XCTUnwrap(parsed.weeks.first?.days.first)
        XCTAssertEqual(day.isTest, true)
        XCTAssertEqual(day.exercises.first?.isTest, true, "inherits the day's test flag")
    }

    func testParserFlagsASingleTestBlockWithoutMarkingTheWholeDay() throws {
        let json = """
        {
          "name": "Conditioning Week",
          "weeks": [
            {
              "days": [
                {
                  "weekday": 2,
                  "title": "Aerobic Run",
                  "focus": "run",
                  "notes": null,
                  "exercises": [
                    { "name": "Warm Up", "sets": 1, "reps_low": 1, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null, "detail": "5'" },
                    { "name": "Test 30m", "sets": 1, "reps_low": 1, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null, "detail": "30m sprint" }
                  ]
                }
              ]
            }
          ]
        }
        """
        let parsed = try TrainerProgramParser.parse(json)
        let day = try XCTUnwrap(parsed.weeks.first?.days.first)
        XCTAssertEqual(day.isTest, false, "the day title itself isn't a test — only one block is")
        XCTAssertEqual(day.exercises[0].isTest, false)
        XCTAssertEqual(day.exercises[1].isTest, true)
    }

    // MARK: - Percentage-of-max is a load, not a test

    func testPercentOfOneRepMaxIsNotATest() {
        XCTAssertFalse(TrainerTestDayDetector.isTestExercise(name: "Squat", detail: "4x5 @ 75% 1RM", notes: nil))
        XCTAssertFalse(TrainerTestDayDetector.isTestExercise(name: "Bench", detail: nil, notes: "70% of your 1RM"))
        XCTAssertFalse(TrainerTestDayDetector.isTestExercise(name: "Deadlift", detail: nil, notes: "80% 5RM"))
    }

    func testItalianPercentOfMassimaleIsNotATest() {
        XCTAssertFalse(TrainerTestDayDetector.isTestExercise(name: "Squat", detail: "80% del massimale", notes: nil))
        XCTAssertFalse(TrainerTestDayDetector.isTestExercise(name: "Panca", detail: "75% dell'massimale", notes: nil))
    }

    func testRealTestStillDetectedNextToAPercentage() {
        XCTAssertTrue(TrainerTestDayDetector.isTestExercise(name: "Squat", detail: "work up to a 1RM, then 5x3 @ 70% 1RM", notes: nil))
        XCTAssertTrue(TrainerTestDayDetector.isTestDay(title: "Test 1RM", notes: "warm-up at 60% 1RM"))
        XCTAssertTrue(TrainerTestDayDetector.isTestExercise(name: "Squat", detail: "lavora al massimale", notes: nil))
    }
}
