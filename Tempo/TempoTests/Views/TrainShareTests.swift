//
// TrainShareTests.swift
// Tempo
//
// The workout summary's share cards carry only numbers read from the session:
// a finished workout, and a personal record with the best it beat.
//

@testable import Tempo
import XCTest

@MainActor
final class TrainShareTests: XCTestCase {
    private func stat(_ card: ShareCardContent, _ label: String) -> String? {
        card.stats.first { $0.label == label }?.value
    }

    func testAFinishedWorkoutCardCarriesItsRealNumbers() {
        let card = TrainShare.workoutCard(
            title: "Push day", elapsedSeconds: 52 * 60 + 20, exercises: 6, sets: 22, volumeKg: 8420.4
        )
        XCTAssertEqual(card.layout, .workout)
        XCTAssertEqual(card.title, "Push day")
        XCTAssertEqual(card.hero, "52")
        XCTAssertEqual(card.heroUnit, "minutes")
        XCTAssertEqual(stat(card, "Exercises"), "6")
        XCTAssertEqual(stat(card, "Sets"), "22")
        XCTAssertNotNil(stat(card, "Volume"))
    }

    func testAWorkoutUnderAMinuteLeadsWithItsSetsNotZeroMinutes() {
        let card = TrainShare.workoutCard(title: "Pull day", elapsedSeconds: 20, exercises: 1, sets: 1, volumeKg: 0)
        XCTAssertEqual(card.hero, "1")
        XCTAssertEqual(card.heroUnit, "set")
        XCTAssertNil(stat(card, "Volume"), "no volume is left out, not shown as 0")
    }

    func testAWeightRecordShowsTheNewBestInTheUsersUnitAndTheOldOne() {
        let record = PersonalRecord(type: .oneRepMax, value: 100, date: Date(), exercise: nil)
        record.exerciseNameSnapshot = "Bench Press"
        let kg = TrainShare.recordCard(record, unit: .kg, before: 92.5)
        XCTAssertEqual(kg.layout, .record)
        XCTAssertEqual(kg.title, "Bench Press")
        XCTAssertEqual(kg.hero, "100")
        XCTAssertEqual(kg.heroUnit, "kg")
        XCTAssertEqual(stat(kg, "Before"), "92.5 kg")

        let lbs = TrainShare.recordCard(record, unit: .lbs, before: 92.5)
        XCTAssertEqual(lbs.hero, "220.5")
        XCTAssertEqual(lbs.heroUnit, "lbs")
        XCTAssertEqual(stat(lbs, "Before"), "203.9 lbs")
    }

    func testARecordWithNothingBeforeItHasNoBeforeLine() {
        let record = PersonalRecord(type: .repMax, value: 60, date: Date(), exercise: nil)
        XCTAssertNil(stat(TrainShare.recordCard(record, unit: .kg, before: nil), "Before"))
        XCTAssertNil(stat(TrainShare.recordCard(record, unit: .kg, before: 0), "Before"))
    }

    func testAMostRepsRecordCountsRepsNotKilos() {
        let record = PersonalRecord(type: .mostReps, value: 12, date: Date(), exercise: nil)
        let card = TrainShare.recordCard(record, unit: .lbs, before: 10)
        XCTAssertEqual(card.hero, "12")
        XCTAssertEqual(card.heroUnit, "reps")
        XCTAssertEqual(stat(card, "Before"), "10 reps")
    }

    func testThePreviousBestIsNilForALiftWithNoEarlierHistory() {
        let record = PersonalRecord(type: .oneRepMax, value: 100, date: Date(), exercise: nil)
        XCTAssertNil(TrainShare.previousBest(of: record), "a record with no lift attached has nothing to compare")
    }
}
