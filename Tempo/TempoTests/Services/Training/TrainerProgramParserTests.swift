//
// TrainerProgramParserTests.swift
// Tempo
//
// Pins the JSON contract between the Sonnet proxy response and
// `[ProgramWeek]`: fenced JSON, weekday auto-assignment for "Day 1/Day 2"
// sources, ranges/percent/RPE/supersets, lb->kg conversion, value clamping,
// and the error paths (malformed / empty). No network — pure parsing.
//
// The "mirrors a real program" tests below fix JSON shaped exactly like
// Sonnet's answer to the combined transcript of two real trainer PDFs (one
// lift-sessions sheet, one conditioning-sessions sheet — see the import
// pipeline's PR description for the source rows): letter-paired supersets
// (A/A, B/B rows), "8+8" per-side reps, a "Weights" percentage -> percent_1rm
// vs. a conditioning intensity percentage -> rpe, conditioning blocks in
// `detail`, and every day weekday: null (a session sheet names no weekday).
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

    func testOutOfRangeWeekdayIsReassignedNotLost() throws {
        let json = #"{"name":"X","weeks":[{"days":[{"weekday":9,"exercises":[{"name":"Squat","sets":3,"reps_low":5}]}]}]}"#
        let result = try TrainerProgramParser.parse(json)
        let weekday = try XCTUnwrap(result.weeks.first?.days.first?.weekday)
        XCTAssertTrue((1 ... 7).contains(weekday))
    }

    // MARK: - weekdayGuessed

    func testWeekdayGuessedIsTrueOnlyForAssignedDays() throws {
        let json = """
        { "name": "P", "weeks": [{ "days": [
          { "weekday": 2, "exercises": [{ "name": "Row", "sets": 3, "reps_low": 10 }] },
          { "weekday": null, "exercises": [{ "name": "Curl", "sets": 3, "reps_low": 10 }] }
        ]}]}
        """
        let parsed = try TrainerProgramParser.parse(json)
        let days = try XCTUnwrap(parsed.weeks.first).days
        XCTAssertEqual(days[0].weekdayGuessed, false)
        XCTAssertEqual(days[1].weekdayGuessed, true)
    }

    // MARK: - Conditioning: detail, per_side, focus

    func testConditioningFocusIsAccepted() throws {
        for focus in ["run", "sprint", "conditioning", "pool", "mobility"] {
            let json = """
            { "name": "P", "weeks": [{ "days": [
              { "weekday": 1, "focus": "\(focus)", "exercises": [{ "name": "Block", "sets": 1, "reps_low": 1, "detail": "20'" }] }
            ]}]}
            """
            let parsed = try TrainerProgramParser.parse(json)
            XCTAssertEqual(parsed.weeks.first?.days.first?.focus, focus, "focus \(focus) should round-trip")
        }
    }

    func testRestAndFootballFocusAreRejected() throws {
        for focus in ["rest", "football"] {
            let json = """
            { "name": "P", "weeks": [{ "days": [
              { "weekday": 1, "focus": "\(focus)", "exercises": [{ "name": "Block", "sets": 1, "reps_low": 1 }] }
            ]}]}
            """
            let parsed = try TrainerProgramParser.parse(json)
            XCTAssertNil(parsed.weeks.first?.days.first?.focus, "\(focus) isn't a schedulable session focus")
        }
    }

    func testDetailAndPerSideRoundTrip() throws {
        let json = """
        { "name": "P", "weeks": [{ "days": [{ "weekday": 1, "focus": "run", "exercises": [
          { "name": "Fartleck", "sets": 1, "reps_low": 1, "detail": "35' — 2' slow / 1' fast / 30\\" walk + juggling", "rpe": 8 },
          { "name": "KT Lat Step Up", "sets": 3, "reps_low": 8, "per_side": true }
        ]}]}]}
        """
        let parsed = try TrainerProgramParser.parse(json)
        let exercises = try XCTUnwrap(parsed.weeks.first).days[0].exercises
        XCTAssertEqual(exercises[0].detail, "35' — 2' slow / 1' fast / 30\" walk + juggling")
        XCTAssertEqual(exercises[0].rpe, 8)
        XCTAssertNil(exercises[0].perSide)
        XCTAssertEqual(exercises[1].perSide, true)
        XCTAssertEqual(exercises[1].repsLow, 8, "per_side: reps_low is the per-side count, not doubled")
        XCTAssertNil(exercises[1].detail)
    }

    // MARK: - Mirrors a real program (two-file lift + conditioning import)

    /// Shaped exactly like Sonnet's answer to the combined transcript of a
    /// real "LIFT SESSIONS.pdf" + "CONDITIONING SESSIONS.pdf" pair: A/A
    /// letter-paired supersets, a "Weights" percentage on the lift sheet
    /// (-> percent_1rm), an intensity percentage on the conditioning sheet
    /// (-> rpe), an "8+8" per-side row, a conditioning block's whole
    /// prescription in `detail`, an ordering note, and every day with no
    /// weekday in the source (a session sheet, not a weekly calendar).
    private static let realProgramMirrorJSON = """
    {
      "name": "Coach — Lift + Conditioning",
      "weeks": [{ "days": [
        {
          "weekday": null, "title": "HYPERTROPHY LIFTING 1", "focus": "full_body", "notes": null,
          "exercises": [
            { "name": "Leg Press", "sets": 3, "reps_low": 8, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": 0.7, "rest_seconds": null, "superset_group": 1, "notes": null },
            { "name": "SA Incline DB Chest Press", "sets": 3, "reps_low": 8, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": 0.7, "rest_seconds": 60, "superset_group": 1, "notes": null },
            { "name": "KT Lat Step Up", "sets": 3, "reps_low": 8, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": 0.7, "rest_seconds": null, "superset_group": 2, "notes": null, "per_side": true },
            { "name": "SA DB Lat Raises", "sets": 3, "reps_low": 8, "reps_high": null, "weight": null, "weight_unit": null, "rpe": null, "percent_1rm": 0.7, "rest_seconds": 60, "superset_group": 2, "notes": null }
          ]
        },
        {
          "weekday": null, "title": "AEROBIC RUN", "focus": "run", "notes": null,
          "exercises": [
            { "name": "Warm Up", "sets": 1, "reps_low": 1, "reps_high": null, "weight": null, "weight_unit": null, "rpe": 6, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": "without ball", "detail": "5'" },
            { "name": "Fartleck", "sets": 1, "reps_low": 1, "reps_high": null, "weight": null, "weight_unit": null, "rpe": 8, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": "with the ball", "detail": "35' — 2' slow / 1' fast / 30\\" walk + juggling" },
            { "name": "Cool Down", "sets": 1, "reps_low": 1, "reps_high": null, "weight": null, "weight_unit": null, "rpe": 6, "percent_1rm": null, "rest_seconds": null, "superset_group": null, "notes": "without ball", "detail": "10'" }
          ]
        },
        {
          "weekday": null, "title": "ANAEROBIC RUN", "focus": "sprint",
          "notes": "Follow the order: S1 - Rest - S2 - Rest - S2 - Rest - S1",
          "exercises": [
            { "name": "Shuttle 1", "sets": 1, "reps_low": 1, "reps_high": null, "weight": null, "weight_unit": null, "rpe": 9, "percent_1rm": null, "rest_seconds": 90, "superset_group": null, "notes": "300y total", "detail": "4 reps of 25y out and back in < 65\\"" },
            { "name": "Shuttle 2", "sets": 1, "reps_low": 1, "reps_high": null, "weight": null, "weight_unit": null, "rpe": 9, "percent_1rm": null, "rest_seconds": 90, "superset_group": null, "notes": "320y total", "detail": "4 reps 80y out and back in < 55\\"" }
          ]
        }
      ]}]
    }
    """

    func testMirrorsRealProgramLiftDaySupersetsAndPercent() throws {
        let parsed = try TrainerProgramParser.parse(Self.realProgramMirrorJSON)
        XCTAssertTrue(parsed.autoAssignedWeekdays, "the source sheet names no weekday at all")
        let liftDay = try XCTUnwrap(parsed.weeks.first?.days.first)
        XCTAssertEqual(liftDay.title, "HYPERTROPHY LIFTING 1")
        XCTAssertEqual(liftDay.focus, "full_body")
        XCTAssertTrue(liftDay.isStrength)
        XCTAssertEqual(liftDay.weekdayGuessed, true)

        let exercises = liftDay.exercises
        XCTAssertEqual(exercises.count, 4)
        // A/A pair -> superset_group 1, C/C pair -> superset_group 2.
        XCTAssertEqual(exercises[0].group, 1)
        XCTAssertEqual(exercises[1].group, 1)
        XCTAssertEqual(exercises[2].group, 2)
        XCTAssertEqual(exercises[3].group, 2)
        // A lift-sheet "Weights" percentage is percent_1rm, never rpe.
        for exercise in exercises {
            XCTAssertEqual(exercise.percentOf1RM, 0.7)
            XCTAssertNil(exercise.rpe)
        }
        // "3 x 8+8" -> per-side.
        XCTAssertEqual(exercises[2].name, "KT Lat Step Up")
        XCTAssertEqual(exercises[2].perSide, true)
        XCTAssertEqual(exercises[2].repsLow, 8)
    }

    func testMirrorsRealProgramConditioningDaysUseDetailAndRPE() throws {
        let parsed = try TrainerProgramParser.parse(Self.realProgramMirrorJSON)
        let days = try XCTUnwrap(parsed.weeks.first).days
        let aerobic = days[1]
        XCTAssertEqual(aerobic.focus, "run")
        XCTAssertFalse(aerobic.isStrength)

        let fartleck = try XCTUnwrap(aerobic.exercises.first { $0.name == "Fartleck" })
        XCTAssertEqual(fartleck.detail, "35' — 2' slow / 1' fast / 30\" walk + juggling")
        // A conditioning-sheet intensity percentage ("80%") is rpe, never percent_1rm.
        XCTAssertEqual(fartleck.rpe, 8)
        XCTAssertNil(fartleck.percentOf1RM)

        let anaerobic = days[2]
        XCTAssertEqual(anaerobic.focus, "sprint")
        XCTAssertEqual(anaerobic.notes, "Follow the order: S1 - Rest - S2 - Rest - S2 - Rest - S1")
        XCTAssertEqual(anaerobic.exercises.map(\.detail), [
            "4 reps of 25y out and back in < 65\"",
            "4 reps 80y out and back in < 55\"",
        ])
    }

    func testMirrorsRealProgramEveryDayHasNoExplicitWeekday() throws {
        let parsed = try TrainerProgramParser.parse(Self.realProgramMirrorJSON)
        let days = try XCTUnwrap(parsed.weeks.first).days
        XCTAssertEqual(days.count, 3)
        XCTAssertTrue(days.allSatisfy { $0.weekdayGuessed == true })
        // assignWeekdays spreads 3 slots across Mon/Wed/Fri as the initial
        // guess (ProgramScheduler re-places them around football later).
        XCTAssertEqual(days.map(\.weekday), [1, 3, 5])
    }
}
