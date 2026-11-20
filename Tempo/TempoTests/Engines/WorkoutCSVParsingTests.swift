//
// WorkoutCSVParsingTests.swift
// Tempo
//
// Realistic Strong / Hevy / hand-made export rows through
// `WorkoutCSVService.parse`: quoted fields with commas and newlines,
// decimal commas, CRLF + BOM, bodyweight rows with an empty weight, rest-timer
// and timed (distance/seconds) rows, and unit detection from headers.
//

@testable import Tempo
import XCTest

final class WorkoutCSVParsingTests: XCTestCase {
    /// Current Strong export: "Weight Unit" column, quoted notes.
    private let strongModern = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Weight Unit,Reps,RPE,Distance,Distance Unit,Seconds,Notes,Workout Notes,Workout Duration
    2025-03-10 07:15:42,"Push Day, Heavy",1h 12m,Bench Press (Barbell),W,"60",lbs,10,,0,,0,,"Felt strong,\nslept well",1h 12m
    2025-03-10 07:15:42,"Push Day, Heavy",1h 12m,Bench Press (Barbell),1,"225",lbs,5,8,0,,0,,"Felt strong,\nslept well",1h 12m
    2025-03-10 07:15:42,"Push Day, Heavy",1h 12m,Bench Press (Barbell),Rest Timer,,,,,,,180,,,1h 12m
    2025-03-10 07:15:42,"Push Day, Heavy",1h 12m,Bench Press (Barbell),D,"185",lbs,8,,0,,0,,,1h 12m
    2025-03-10 07:15:42,"Push Day, Heavy",1h 12m,"Curl, 21s (Dumbbell)",1,"27,5",lbs,7,,0,,0,,,1h 12m
    2025-03-10 07:15:42,"Push Day, Heavy",1h 12m,Pull Up,1,,lbs,8,,0,,0,,,1h 12m
    2025-03-10 07:15:42,"Push Day, Heavy",1h 12m,Plank,1,0,lbs,0,,0,,60,,,1h 12m
    2025-03-10 07:15:42,"Push Day, Heavy",1h 12m,Treadmill,1,0,lbs,0,,2.5,mi,900,,,1h 12m
    """

    /// Older Strong export: no unit column at all (the unit is a setting in
    /// the app, so the file can't say).
    private let strongLegacy = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
    2023-02-14 11:30:08,Legs,52m,Squat (Barbell),1,315,5,0,0,,,
    """

    private let hevyLbs = """
    "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_miles","duration_seconds","rpe"
    "Morning Workout","20 Jul 2026, 07:00","20 Jul 2026, 08:05","","Bench Press (Barbell)","","",0,"warmup",95,10,,,
    "Morning Workout","20 Jul 2026, 07:00","20 Jul 2026, 08:05","","Bench Press (Barbell)","","",1,"normal",185,5,,,9
    "Morning Workout","20 Jul 2026, 07:00","20 Jul 2026, 08:05","","Bench Press (Barbell)","","",2,"failure",185,4,,,
    "Morning Workout","20 Jul 2026, 07:00","20 Jul 2026, 08:05","","Pull Up","","",0,"normal",,12,,,
    "Morning Workout","20 Jul 2026, 07:00","20 Jul 2026, 08:05","","Plank","","",0,"normal",,,,60,
    """

    private let hevyKg = """
    "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
    "Leg Day","2026-07-21T18:00:00Z","2026-07-21T19:00:00Z","","Squat (Barbell)","","",0,"normal","102,5",5,,,
    """

    func testModernStrongKeepsRealSetsAndDropsTheRest() throws {
        let file = try WorkoutCSVService.parse(strongModern)
        XCTAssertEqual(file.format, .strong)
        // 1 working bench + 1 drop + curl + pull-up. Warmup, rest timer,
        // plank (time only) and treadmill (distance only) are not sets.
        XCTAssertEqual(file.sets.map(\.exercise), [
            "Bench Press (Barbell)", "Bench Press (Barbell)", "Curl, 21s (Dumbbell)", "Pull Up",
        ])
        XCTAssertEqual(file.sets.first?.workoutName, "Push Day, Heavy")
        XCTAssertEqual(file.sets.first?.durationMinutes, 72)
        XCTAssertEqual(file.declaredUnit, .lbs)
    }

    func testDecimalCommaInsideQuotesAndEmptyBodyweightWeight() throws {
        let file = try WorkoutCSVService.parse(strongModern)
        let curl = try XCTUnwrap(file.sets.first { $0.exercise.hasPrefix("Curl") })
        XCTAssertEqual(curl.weight, 27.5)
        let pullUp = try XCTUnwrap(file.sets.first { $0.exercise == "Pull Up" })
        XCTAssertNil(pullUp.weight)
        XCTAssertNil(pullUp.weightKg(assuming: .kg), "Bodyweight stays nil, never 0 kg")
        XCTAssertEqual(pullUp.reps, 8)
    }

    func testLegacyStrongDeclaresNoUnit() throws {
        let file = try WorkoutCSVService.parse(strongLegacy)
        XCTAssertNil(file.declaredUnit, "No unit column: the caller has to ask")
        XCTAssertEqual(file.sets.first?.weight, 315)
        XCTAssertNil(file.sets.first?.unit)
    }

    func testHevyPoundsExportIsReadNotDropped() throws {
        let file = try WorkoutCSVService.parse(hevyLbs)
        XCTAssertEqual(file.format, .hevy)
        XCTAssertEqual(file.declaredUnit, .lbs)
        // warmup dropped; failure set kept; plank (no reps) dropped.
        XCTAssertEqual(file.sets.map(\.reps), [5, 4, 12])
        XCTAssertEqual(file.sets.first?.weight, 185, "weight_lbs column is read")
        XCTAssertEqual(file.sets.first?.rpe, 9)
        XCTAssertEqual(file.sets.first?.durationMinutes, 65)
        XCTAssertNil(file.sets.last?.weight)
        let parts = try Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: XCTUnwrap(file.sets.first?.start)
        )
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 7, 20, 7, 0])
    }

    func testHevyKgWithDecimalCommaAndIsoDates() throws {
        let file = try WorkoutCSVService.parse(hevyKg)
        XCTAssertEqual(file.declaredUnit, .kg)
        XCTAssertEqual(file.sets.first?.weight, 102.5)
        XCTAssertEqual(file.sets.first?.durationMinutes, 60)
    }

    func testCRLFAndByteOrderMark() throws {
        let crlf = "\u{FEFF}" + strongLegacy.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"
        let file = try WorkoutCSVService.parse(crlf)
        XCTAssertEqual(file.format, .strong, "BOM must not corrupt the first header")
        XCTAssertEqual(file.sets.count, 1)
        XCTAssertEqual(file.sets.first?.reps, 5)
    }

    func testGenericHeadersWithUnitInTheName() throws {
        let csv = """
        Date,Exercise,Weight (lbs),Reps
        2026-01-05,Back Squat,"225",5
        2026-01-05,Chin Up,,10
        """
        let file = try WorkoutCSVService.parse(csv)
        XCTAssertEqual(file.format, .generic)
        XCTAssertEqual(file.declaredUnit, .lbs)
        XCTAssertEqual(file.sets.count, 2)
        XCTAssertEqual(try XCTUnwrap(file.sets.first?.weightKg(assuming: .kg)), 225 / 2.20462, accuracy: 0.001)
    }

    func testGenericKgHeaderAndExerciseNameColumn() throws {
        let csv = "date,exercise name,weight_kg,reps\n2026-01-05 10:00,Row,60,8\n"
        let file = try WorkoutCSVService.parse(csv)
        XCTAssertEqual(file.format, .generic)
        XCTAssertEqual(file.declaredUnit, .kg)
        XCTAssertEqual(file.sets.first?.exercise, "Row")
    }

    func testThousandsCommaAndDecimalComma() {
        XCTAssertEqual(WorkoutCSVService.double("1,082.5"), 1082.5)
        XCTAssertEqual(WorkoutCSVService.double("82,5"), 82.5)
        XCTAssertEqual(WorkoutCSVService.double("82.5"), 82.5)
        XCTAssertNil(WorkoutCSVService.double(""))
        XCTAssertNil(WorkoutCSVService.double("abc"))
    }

    func testNoRepsAnywhereIsNoWorkouts() {
        let csv = "Date,Workout Name,Exercise Name,Set Order,Weight,Reps\n2026-01-05 10:00,Cardio,Run,1,0,0\n"
        XCTAssertThrowsError(try WorkoutCSVService.parse(csv)) { error in
            XCTAssertEqual(error as? WorkoutCSVService.ImportError, .noWorkouts)
        }
    }
}
