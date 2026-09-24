//
// TrainerProgramParserTests.swift
// Tempo
//
// Pins the JSON contract between the Sonnet proxy response and
// `[ProgramWeek]`: fenced JSON, weekday auto-assignment for "Day 1/Day 2"
// sources, ranges/percent/RPE/supersets, lb->kg conversion, value clamping,
// and the error paths (malformed / empty). No network — pure parsing.
//

@testable import Tempo
import XCTest

final class TrainerProgramParserTests: XCTestCase {
    // MARK: - Happy path: a single explicit week

    func testParsesSimpleWeekWithWeekdays() throws {
        let json = """
        {
          "name": "Push Pull Legs",
          "weeks": [
            {
              "days": [
                {
                  "weekday": 1,
                  "title": "Push",
                  "focus": "push",
                  "notes": null,
                  "exercises": [
                    {
                      "name": "Bench Press",
                      "sets": 4,
                      "reps_low": 6,
                      "reps_high": 8,
                      "weight": 80,
                      "weight_unit": "kg",
                      "rpe": 8,
                      "percent_1rm": null,
                      "rest_seconds": 120,
                      "superset_group": null,
                      "notes": null
                    }
                  ]
                }
              ]
            }
          ]
        }
        """
        let parsed = try TrainerProgramParser.parse(json)
        XCTAssertEqual(parsed.name, "Push Pull Legs")
        XCTAssertFalse(parsed.autoAssignedWeekdays)
        XCTAssertEqual(parsed.weeks.count, 1)
        let day = try XCTUnwrap(parsed.weeks.first?.days.first)
        XCTAssertEqual(day.weekday, 1)
        XCTAssertEqual(day.focus, "push")
        let exercise = try XCTUnwrap(day.exercises.first)
        XCTAssertEqual(exercise.name, "Bench Press")
        XCTAssertEqual(exercise.sets, 4)
        XCTAssertEqual(exercise.repsLow, 6)
        XCTAssertEqual(exercise.repsHigh, 8)
        XCTAssertEqual(exercise.weightKg, 80)
        XCTAssertEqual(exercise.rpe, 8)
        XCTAssertEqual(exercise.restSeconds, 120)
        XCTAssertNil(exercise.exerciseID, "matching happens later, on save")
    }

    // MARK: - Day-numbered programs (no weekday) -> auto-assignment

    func testDayNumberedProgramSpreadsAcrossTheWeek() throws {
        let json = """
        {
          "name": "Coach Program",
          "weeks": [
            { "days": [
              { "weekday": null, "title": "Day 1", "focus": null, "notes": null, "exercises": [
                { "name": "Squat", "sets": 5, "reps_low": 5, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null }
              ]},
              { "weekday": null, "title": "Day 2", "focus": null, "notes": null, "exercises": [
                { "name": "Bench", "sets": 5, "reps_low": 5, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null }
              ]},
              { "weekday": null, "title": "Day 3", "focus": null, "notes": null, "exercises": [
                { "name": "Deadlift", "sets": 5, "reps_low": 5, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null }
              ]}
            ]}
          ]
        }
        """
        let parsed = try TrainerProgramParser.parse(json)
        XCTAssertTrue(parsed.autoAssignedWeekdays)
        let weekdays = try XCTUnwrap(parsed.weeks.first).days.map(\.weekday)
        XCTAssertEqual(weekdays, [1, 3, 5], "3 days spread Mon/Wed/Fri")
    }

    func testExplicitWeekdaysAreNeverOverridden() throws {
        let json = """
        {
          "name": "P",
          "weeks": [{ "days": [
            { "weekday": 2, "title": null, "focus": null, "notes": null, "exercises": [
              { "name": "Row", "sets": 3, "reps_low": 10, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null }
            ]},
            { "weekday": null, "title": null, "focus": null, "notes": null, "exercises": [
              { "name": "Curl", "sets": 3, "reps_low": 10, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null }
            ]}
          ]}]
        }
        """
        let parsed = try TrainerProgramParser.parse(json)
        let days = try XCTUnwrap(parsed.weeks.first).days
        XCTAssertEqual(days[0].weekday, 2, "explicit weekday kept as-is")
        XCTAssertTrue(parsed.autoAssignedWeekdays)
    }

    // MARK: - Ranges, percent, RPE, supersets

    func testRepRangesPercentRPEAndSupersets() throws {
        let json = """
        {
          "name": "P",
          "weeks": [{ "days": [{ "weekday": 1, "title": null, "focus": null, "notes": null, "exercises": [
            { "name": "Squat A1", "sets": 4, "reps_low": 8, "reps_high": 12, "weight": null, "weight_unit": null, "rpe": 8.5, "percent_1rm": 0.75, "rest_seconds": 90, "superset_group": 1, "notes": null },
            { "name": "Lunge A2", "sets": 4, "reps_low": 8, "reps_high": 12, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": 90, "superset_group": 1, "notes": "AMRAP" }
          ]}]}]
        }
        """
        let parsed = try TrainerProgramParser.parse(json)
        let exercises = try XCTUnwrap(parsed.weeks.first).days[0].exercises
        XCTAssertEqual(exercises[0].repsLow, 8)
        XCTAssertEqual(exercises[0].repsHigh, 12)
        XCTAssertEqual(exercises[0].rpe, 8.5)
        XCTAssertEqual(exercises[0].percentOf1RM, 0.75)
        XCTAssertEqual(exercises[0].group, 1)
        XCTAssertEqual(exercises[1].group, 1)
        XCTAssertEqual(exercises[1].notes, "AMRAP")
    }

    func testPercentGivenAsWholeNumberIsNormalizedToAFraction() throws {
        let json = """
        {
          "name": "P",
          "weeks": [{ "days": [{ "weekday": 1, "title": null, "focus": null, "notes": null, "exercises": [
            { "name": "Squat", "sets": 3, "reps_low": 5, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": 75, "rest_seconds": null, "superset_group": null, "notes": null }
          ]}]}]
        }
        """
        let parsed = try TrainerProgramParser.parse(json)
        XCTAssertEqual(try XCTUnwrap(parsed.weeks.first).days[0].exercises[0].percentOf1RM, 0.75)
    }

    // MARK: - Unit conversion

    func testPoundsAreConvertedToKilograms() throws {
        let json = """
        {
          "name": "P",
          "weeks": [{ "days": [{ "weekday": 1, "title": null, "focus": null, "notes": null, "exercises": [
            { "name": "Bench", "sets": 3, "reps_low": 5, "reps_high": null, "weight": 225, "weight_unit": "lb", "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null }
          ]}]}]
        }
        """
        let parsed = try TrainerProgramParser.parse(json)
        let weightKg = try XCTUnwrap(parsed.weeks.first?.days.first?.exercises.first?.weightKg)
        XCTAssertEqual(weightKg, 225 / 2.20462, accuracy: 0.01)
    }

    // MARK: - Clamping

    func testAbsurdValuesAreClamped() throws {
        let json = """
        {
          "name": "P",
          "weeks": [{ "days": [{ "weekday": 1, "title": null, "focus": null, "notes": null, "exercises": [
            { "name": "Bench", "sets": 999, "reps_low": 1, "reps_high": null, "weight": 99999, "weight_unit": "kg", "rpe": 55, "percent_1rm": null, "rest_seconds": 99999, "superset_group": null, "notes": null }
          ]}]}]
        }
        """
        let parsed = try TrainerProgramParser.parse(json)
        let exercise = try XCTUnwrap(parsed.weeks.first?.days.first?.exercises.first)
        XCTAssertEqual(exercise.sets, 20)
        XCTAssertEqual(exercise.weightKg, 500)
        XCTAssertEqual(exercise.rpe, 10)
        XCTAssertEqual(exercise.restSeconds, 900)
    }

    // MARK: - Fenced JSON / stray prose

    func testStripsMarkdownCodeFence() throws {
        let json = """
        Here you go:
        ```json
        {
          "name": "Fenced",
          "weeks": [{ "days": [{ "weekday": 1, "title": null, "focus": null, "notes": null, "exercises": [
            { "name": "Row", "sets": 3, "reps_low": 10, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null }
          ]}]}]
        }
        ```
        Hope that helps!
        """
        let parsed = try TrainerProgramParser.parse(json)
        XCTAssertEqual(parsed.name, "Fenced")
    }

    // MARK: - Errors

    func testMalformedJSONThrowsInvalidJSON() {
        XCTAssertThrowsError(try TrainerProgramParser.parse("not json at all")) { error in
            XCTAssertEqual(error as? TrainerProgramParser.ParseError, .invalidJSON)
        }
    }

    func testTruncatedJSONThrowsInvalidJSON() {
        let truncated = """
        { "name": "P", "weeks": [ { "days": [ { "weekday": 1,
        """
        XCTAssertThrowsError(try TrainerProgramParser.parse(truncated))
    }

    func testEmptyProgramThrowsEmptyProgram() {
        let json = #"{"name": "", "weeks": []}"#
        XCTAssertThrowsError(try TrainerProgramParser.parse(json)) { error in
            XCTAssertEqual(error as? TrainerProgramParser.ParseError, .emptyProgram)
        }
    }

    func testWeeksWithNoExercisesThrowsEmptyProgram() {
        let json = """
        { "name": "P", "weeks": [{ "days": [{ "weekday": 1, "title": null, "focus": null, "notes": null, "exercises": [] }]}]}
        """
        XCTAssertThrowsError(try TrainerProgramParser.parse(json)) { error in
            XCTAssertEqual(error as? TrainerProgramParser.ParseError, .emptyProgram)
        }
    }

    // MARK: - Multi-week

    func testMultipleWeeksPreserveOrder() throws {
        let json = """
        {
          "name": "Block",
          "weeks": [
            { "days": [{ "weekday": 1, "title": "W1D1", "focus": null, "notes": null, "exercises": [
              { "name": "Squat", "sets": 3, "reps_low": 8, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null }
            ]}]},
            { "days": [{ "weekday": 1, "title": "W2D1", "focus": null, "notes": null, "exercises": [
              { "name": "Squat", "sets": 3, "reps_low": 6, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": null }
            ]}]}
          ]
        }
        """
        let parsed = try TrainerProgramParser.parse(json)
        XCTAssertEqual(parsed.weeks.count, 2)
        XCTAssertEqual(parsed.weeks[0].days.first?.title, "W1D1")
        XCTAssertEqual(parsed.weeks[1].days.first?.title, "W2D1")
    }
}
