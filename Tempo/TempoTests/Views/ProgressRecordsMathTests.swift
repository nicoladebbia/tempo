//
// ProgressRecordsMathTests.swift
// Tempo
//
// The Records tab of the Progress page: which record speaks for a lift, how
// recent and last-30-day records are counted, and the words for each kind of
// record.
//

@testable import Tempo
import XCTest

final class ProgressRecordsMathTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
    }

    private func lift(_ name: String) -> Exercise {
        Exercise(name: name, muscleGroup: .chest, equipment: .barbell, movementPattern: .horizontalPush, isCompound: true)
    }

    func testBestPerExercisePrefersAnEstimatedOneRepMaxThenTheBiggestValue() {
        let bench = lift("Bench Press")
        let records = [
            PersonalRecord(type: .repMax, value: 100, date: daysAgo(1), exercise: bench),
            PersonalRecord(type: .oneRepMax, value: 112, date: daysAgo(10), exercise: bench),
            PersonalRecord(type: .oneRepMax, value: 118, date: daysAgo(3), exercise: bench),
            PersonalRecord(type: .volume, value: 4000, date: daysAgo(2), exercise: bench),
        ]
        let best = ProgressRecordsMath.bestPerExercise(records)
        XCTAssertEqual(best.count, 1)
        XCTAssertEqual(best[0].record.type, .oneRepMax)
        XCTAssertEqual(best[0].record.value, 118)
        XCTAssertEqual(best[0].recordCount, 4)
    }

    func testBestPerExerciseFallsBackThroughTheTypeOrder() {
        let pullUp = lift("Pull-Up")
        let curl = lift("Curl")
        let records = [
            PersonalRecord(type: .volume, value: 900, date: daysAgo(4), exercise: pullUp),
            PersonalRecord(type: .mostReps, value: 12, date: daysAgo(6), exercise: pullUp),
            PersonalRecord(type: .volume, value: 700, date: daysAgo(1), exercise: curl),
        ]
        let best = ProgressRecordsMath.bestPerExercise(records)
        XCTAssertEqual(best.first { $0.name == "Pull-Up" }?.record.type, .mostReps)
        XCTAssertEqual(best.first { $0.name == "Curl" }?.record.type, .volume)
    }

    func testLiftsAreOrderedByTheirNewestRecord() {
        let squat = lift("Squat")
        let row = lift("Row")
        let records = [
            PersonalRecord(type: .oneRepMax, value: 150, date: daysAgo(20), exercise: squat),
            PersonalRecord(type: .oneRepMax, value: 90, date: daysAgo(2), exercise: row),
        ]
        XCTAssertEqual(ProgressRecordsMath.bestPerExercise(records).map(\.name), ["Row", "Squat"])
    }

    func testARecordOfADeletedExerciseKeepsItsNameAndStaysOneRow() {
        let ghost = lift("Zercher Squat")
        let first = PersonalRecord(type: .oneRepMax, value: 100, date: daysAgo(9), exercise: ghost)
        let second = PersonalRecord(type: .oneRepMax, value: 105, date: daysAgo(2), exercise: ghost)
        // The exercise is gone; only the snapshot remains.
        first.exercise = nil
        second.exercise = nil
        let best = ProgressRecordsMath.bestPerExercise([first, second])
        XCTAssertEqual(best.count, 1)
        XCTAssertEqual(best[0].name, "Zercher Squat")
        XCTAssertNil(best[0].exercise)
        XCTAssertEqual(best[0].record.value, 105)
    }

    func testRecentIsNewestFirstAndCapped() {
        let bench = lift("Bench Press")
        let records = (0 ..< 10).map { PersonalRecord(type: .oneRepMax, value: Double(100 + $0), date: daysAgo(10 - $0), exercise: bench) }
        let recent = ProgressRecordsMath.recent(records, limit: 3)
        XCTAssertEqual(recent.map(\.value), [109, 108, 107])
    }

    func testCountOfTheLastThirtyDays() {
        let bench = lift("Bench Press")
        let records = [
            PersonalRecord(type: .oneRepMax, value: 100, date: daysAgo(0), exercise: bench),
            PersonalRecord(type: .oneRepMax, value: 100, date: daysAgo(29), exercise: bench),
            PersonalRecord(type: .oneRepMax, value: 100, date: daysAgo(31), exercise: bench),
        ]
        XCTAssertEqual(ProgressRecordsMath.count(records, lastDays: 30, now: now), 2)
        XCTAssertEqual(ProgressRecordsMath.count([], lastDays: 30, now: now), 0)
    }

    func testKindNamesEachRecordInWords() {
        let bench = lift("Bench Press")
        XCTAssertEqual(ProgressRecordsMath.kind(PersonalRecord(type: .oneRepMax, value: 1, date: now, exercise: bench)), "Estimated 1RM")
        XCTAssertEqual(ProgressRecordsMath.kind(PersonalRecord(type: .volume, value: 1, date: now, exercise: bench)), "Best session volume")
        XCTAssertEqual(
            ProgressRecordsMath.kind(PersonalRecord(type: .mostReps, value: 1, date: now, exercise: bench)),
            "Most reps in a set"
        )
        XCTAssertEqual(ProgressRecordsMath.kind(PersonalRecord(type: .repMax, value: 1, date: now, exercise: bench)), "Heaviest weight")
        XCTAssertEqual(
            ProgressRecordsMath.kind(PersonalRecord(type: .repMax, value: 1, date: now, contextReps: 5, exercise: bench)),
            "Heaviest weight, 5 reps"
        )
        XCTAssertEqual(
            ProgressRecordsMath.kind(PersonalRecord(type: .repMax, value: 1, date: now, contextReps: 1, exercise: bench)),
            "Heaviest weight, 1 rep"
        )
        XCTAssertEqual(
            ProgressRecordsMath.kind(PersonalRecord(type: .repMax, value: 1, date: now, context: "82kg x 3 reps", exercise: bench)),
            "Heaviest weight, 3 reps"
        )
    }
}
