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

    func testBodyweightSetsReadBWNeverZero() {
        XCTAssertEqual(WeightFormat.load(kg: 0, unit: .kg), "BW")
        XCTAssertEqual(WeightFormat.load(kg: nil, unit: .lbs), "BW")
        XCTAssertEqual(WeightFormat.load(kg: 20, unit: .kg), "20 kg")
        XCTAssertEqual(WeightFormat.compactLoad(kg: 0, unit: .kg), "BW")
    }

    func testBodyweightRecapShowsRepsNotZeroKg() {
        let delta = WeekOverWeekProgress.ExerciseDelta(
            exerciseID: UUID(), name: "Pull-up", currentDate: Date(), previousDate: Date(),
            currentBestWeightKg: 0, currentBestReps: 12, previousBestWeightKg: 0, previousBestReps: 10,
            e1RMDelta: nil, volumeDelta: nil
        )
        XCTAssertEqual(delta.recapLine(unit: .kg), "Pull-up BW × 10→12")
    }

    func testBodyweightSetLoadsAreCompactAndSigned() {
        XCTAssertEqual(WeightFormat.compactSetLoad(kg: 80, addedKg: 0, bodyweight: true, unit: .kg), "BW")
        XCTAssertEqual(WeightFormat.compactSetLoad(kg: 82.5, addedKg: 2.5, bodyweight: true, unit: .kg), "BW+2.5")
        XCTAssertEqual(WeightFormat.compactSetLoad(kg: 40, addedKg: -40, bodyweight: true, unit: .kg), "BW−40")
        let lbs = WeightFormat.compactSetLoad(kg: 80, addedKg: -18.1437, bodyweight: true, unit: .lbs)
        XCTAssertEqual(lbs, "BW−40")
        XCTAssertEqual(WeightFormat.compactSetLoad(kg: 62.5, addedKg: nil, bodyweight: false, unit: .kg), "62.5")
        XCTAssertEqual(WeightFormat.setLoad(kg: 40, addedKg: -18.1437, bodyweight: true, unit: .lbs), "BW − 40 lbs")
    }

    func testCompactVolumeStaysShort() {
        XCTAssertEqual(WeightFormat.compactVolume(kg: 999, unit: .kg), "999")
        XCTAssertEqual(WeightFormat.compactVolume(kg: 12300, unit: .kg), "12.3k")
        XCTAssertEqual(WeightFormat.compactVolume(kg: 1_000_000, unit: .kg), "1M")
        XCTAssertEqual(WeightFormat.compactVolume(kg: 3_953_700 / 2.20462, unit: .lbs), "3.95M")
    }
}
