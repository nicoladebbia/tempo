//
// ShelfLifeEstimatorTests.swift
// Tempo
//

@testable import Tempo
import XCTest

final class ShelfLifeEstimatorTests: XCTestCase {
    // MARK: - Table matches

    func testEstimate_chickenBreastFridge_matchesTable() {
        let (days, matched) = ShelfLifeEstimator.estimate(canonicalName: "chicken breast", storageLocation: .fridge)
        XCTAssertEqual(days, 2)
        XCTAssertTrue(matched)
    }

    func testEstimate_chickenBreastFreezer_matchesTable() {
        let (days, matched) = ShelfLifeEstimator.estimate(canonicalName: "chicken breast", storageLocation: .freezer)
        XCTAssertEqual(days, 270)
        XCTAssertTrue(matched)
    }

    func testEstimate_substringMatch_worksOnCompoundNames() {
        // "grilled chicken breast" contains "chicken breast" as a substring.
        let (days, matched) = ShelfLifeEstimator.estimate(canonicalName: "grilled chicken breast", storageLocation: .fridge)
        XCTAssertEqual(days, 2)
        XCTAssertTrue(matched)
    }

    func testEstimate_moreSpecificKeywordWinsOverGeneric() {
        // "chicken breast" (2 days fridge) is listed before generic "chicken"
        // (also 2 days here, but distinguishing matters for other pairs like
        // ground beef vs beef steak).
        let (days, matched) = ShelfLifeEstimator.estimate(canonicalName: "ground beef", storageLocation: .freezer)
        XCTAssertEqual(days, 120, "ground beef's own rule, not a generic beef fallback")
        XCTAssertTrue(matched)
    }

    // MARK: - Unmatched → generic fallback

    func testEstimate_unknownFood_usesGenericFallback() {
        let (days, matched) = ShelfLifeEstimator.estimate(canonicalName: "dragonfruit smoothie mix", storageLocation: .fridge)
        XCTAssertEqual(days, ShelfLifeEstimator.genericFallbackDays[.fridge])
        XCTAssertFalse(matched)
    }

    func testIsUnmatched_trueForUnknownFood() {
        XCTAssertTrue(ShelfLifeEstimator.isUnmatched(canonicalName: "space dust", storageLocation: .pantry))
    }

    func testIsUnmatched_falseForKnownFood() {
        XCTAssertFalse(ShelfLifeEstimator.isUnmatched(canonicalName: "rice", storageLocation: .pantry))
    }

    // MARK: - Cooked / prepped override

    func testEstimate_cookedOverridesRawRule_fridge() {
        let (days, matched) = ShelfLifeEstimator.estimate(
            canonicalName: "chicken breast", storageLocation: .fridge, isCooked: true
        )
        XCTAssertEqual(days, ShelfLifeEstimator.cookedFridgeDays)
        XCTAssertTrue(matched)
    }

    func testEstimate_cookedOverridesRawRule_freezer() {
        let (days, _) = ShelfLifeEstimator.estimate(
            canonicalName: "chicken breast", storageLocation: .freezer, isCooked: true
        )
        XCTAssertEqual(days, ShelfLifeEstimator.cookedFreezerDays)
    }

    func testEstimate_preppedAlsoOverridesRawRule() {
        let (days, _) = ShelfLifeEstimator.estimate(
            canonicalName: "rice", storageLocation: .fridge, isPrepped: true
        )
        XCTAssertEqual(days, ShelfLifeEstimator.cookedFridgeDays, "Prepped leftovers use the cooked-food clock too")
    }

    // MARK: - Location change recomputes a different estimate

    func testEstimate_locationChange_fridgeToFreezerExtendsClock() {
        let (fridgeDays, _) = ShelfLifeEstimator.estimate(canonicalName: "salmon", storageLocation: .fridge)
        let (freezerDays, _) = ShelfLifeEstimator.estimate(canonicalName: "salmon", storageLocation: .freezer)
        XCTAssertGreaterThan(freezerDays, fridgeDays, "Moving to the freezer must extend, not shorten, the clock")
    }

    // MARK: - useByDate

    func testUseByDate_addsDaysToBaseDate() throws {
        let base = Date(timeIntervalSince1970: 0)
        let result = ShelfLifeEstimator.useByDate(from: base, canonicalName: "milk", storageLocation: .fridge)
        let expected = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: base))
        XCTAssertEqual(result.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }
}
