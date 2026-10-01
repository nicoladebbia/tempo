//
// WeightFormatTests.swift
// Tempo
//
// One formatter for every stored-kg weight: rounds (never truncates), keeps
// a real half step, drops ".0", and speaks the user's unit.
//

@testable import Tempo
import XCTest

final class WeightFormatTests: XCTestCase {
    func testPoundsRoundTripDoesNotLoseAPound() {
        let storedKg = WeightUnit.lbs.convert(155, to: .kg) // 70.3068…
        XCTAssertEqual(WeightFormat.text(kg: storedKg, unit: .lbs), "155 lbs", "Was '154' via Int() truncation")
    }

    func testHalfKiloStepIsKept() {
        XCTAssertEqual(WeightFormat.text(kg: 62.5, unit: .kg), "62.5 kg", "Was '62' via %.0f / Int()")
        XCTAssertEqual(WeightFormat.text(kg: 60, unit: .kg), "60 kg")
    }

    func testFloatNoiseIsRoundedAway() {
        XCTAssertEqual(WeightFormat.number(kg: 79.99999, unit: .kg), "80")
        XCTAssertEqual(WeightFormat.number(kg: 22.549, unit: .kg), "22.5")
    }

    func testVolumeUsesUsersUnit() {
        XCTAssertEqual(WeightFormat.volumeText(kg: 500, unit: .kg), "500 kg")
        XCTAssertEqual(WeightFormat.volumeText(kg: 1000, unit: .lbs), "2.2k lbs")
        XCTAssertEqual(WeightFormat.volumeText(kg: 360.6, unit: .kg), "361 kg", "Rounded, not truncated")
    }

    func testDecimalCommaIsAccepted() {
        XCTAssertEqual(WeightFormat.parseDecimal("5,2"), 5.2)
        XCTAssertEqual(WeightFormat.parseDecimal(" 62.5 "), 62.5)
        XCTAssertNil(WeightFormat.parseDecimal(""))
        XCTAssertNil(WeightFormat.parseDecimal("abc"))
    }

    func testWeekOverWeekRecapSpeaksTheUsersUnit() {
        let delta = WeekOverWeekProgress.ExerciseDelta(
            exerciseID: UUID(), name: "RDL", currentDate: Date(), previousDate: Date(),
            currentBestWeightKg: 65, currentBestReps: 8, previousBestWeightKg: 60, previousBestReps: 8,
            e1RMDelta: nil, volumeDelta: nil
        )
        XCTAssertEqual(delta.recapLine(unit: .kg), "RDL 60→65 kg")
        XCTAssertEqual(delta.recapLine(unit: .lbs), "RDL 132.3→143.3 lbs")
        XCTAssertEqual(delta.weightChangeText, "60→65 kg", "The trainer report stays in kg")
    }
}
