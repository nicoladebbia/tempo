//
// NumericEntrySheetTests.swift
// Tempo
//
// Created by Tempo on 9/23/26.
//
//

@testable import Tempo
import XCTest

final class NumericEntrySheetTests: XCTestCase {
    // MARK: - sanitize

    func testSanitizeKeepsOnlyDigitsAndOneDecimalPoint() {
        XCTAssertEqual(NumericEntrySheet.sanitize("82.5", allowNegative: false), "82.5")
        XCTAssertEqual(NumericEntrySheet.sanitize("82,5", allowNegative: false), "82.5", "Comma normalizes to a dot")
        XCTAssertEqual(NumericEntrySheet.sanitize("8a2.5x", allowNegative: false), "82.5", "Non-digits are dropped")
        XCTAssertEqual(NumericEntrySheet.sanitize("8.2.5", allowNegative: false), "8.25", "A second dot is dropped, not appended")
    }

    func testSanitizeDropsMinusWhenNegativeNotAllowed() {
        XCTAssertEqual(NumericEntrySheet.sanitize("-20", allowNegative: false), "20")
    }

    func testSanitizeKeepsLeadingMinusWhenNegativeAllowed() {
        XCTAssertEqual(NumericEntrySheet.sanitize("-20", allowNegative: true), "-20")
    }

    func testSanitizeOnlyAcceptsMinusAtLeadingPosition() {
        XCTAssertEqual(
            NumericEntrySheet.sanitize("2-0", allowNegative: true),
            "20",
            "A minus anywhere but the first character is never a valid sign"
        )
    }

    // MARK: - parseAndSnap

    func testParseAndSnapReturnsNilForEmptyOrUnparsableText() {
        XCTAssertNil(NumericEntrySheet.parseAndSnap("", range: 0 ... 500, snap: { $0 }))
        XCTAssertNil(NumericEntrySheet.parseAndSnap("-", range: 0 ... 500, snap: { $0 }))
        XCTAssertNil(NumericEntrySheet.parseAndSnap("12.5.6", range: 0 ... 500, snap: { $0 }))
    }

    func testParseAndSnapClampsToRangeBeforeSnapping() {
        var sawValue: Double?
        let result = NumericEntrySheet.parseAndSnap("9999", range: 0 ... 500, snap: {
            sawValue = $0
            return $0
        })
        XCTAssertEqual(result, 500)
        XCTAssertEqual(sawValue, 500, "snap() receives the CLAMPED value, not the raw typed one")
    }

    func testParseAndSnapAppliesTheSnapClosure() {
        // A real weight-entry snap: WeightConverter.loadableKg for a barbell.
        let result = NumericEntrySheet.parseAndSnap("83", range: 0 ... 500) { display in
            WeightConverter.loadableKg(display, equipment: .barbell, unit: .kg)
        }
        XCTAssertEqual(result, 82.5, "83kg snaps down to the nearest 2.5kg barbell increment")
    }

    func testParseAndSnapHandlesNegativeAddedLoadRange() {
        let result = NumericEntrySheet.parseAndSnap("-13", range: -500 ... 500) { ($0 / 2.5).rounded() * 2.5 }
        XCTAssertEqual(result, -12.5)
    }

    // MARK: - Wheel value builders

    func testWeightWheelValuesStepsFromZeroToUpperBound() {
        let values = NumericEntrySheet.weightWheelValues(step: 2.5, upperBound: 10)
        XCTAssertEqual(values, [0, 2.5, 5, 7.5, 10])
    }

    func testWeightWheelValuesSupportsANegativeLowerBoundForAddedLoad() {
        let values = NumericEntrySheet.weightWheelValues(step: 5, lowerBound: -10, upperBound: 10)
        XCTAssertEqual(values, [-10, -5, 0, 5, 10])
    }

    func testWeightWheelValuesIsEmptyForAnInvalidRange() {
        XCTAssertEqual(NumericEntrySheet.weightWheelValues(step: 2.5, lowerBound: 10, upperBound: 5), [])
        XCTAssertEqual(NumericEntrySheet.weightWheelValues(step: 0, upperBound: 10), [])
    }

    func testIntWheelValuesCoversTheWholeRepsRange() {
        let values = NumericEntrySheet.intWheelValues(1 ... 5)
        XCTAssertEqual(values, [1, 2, 3, 4, 5])
    }
}
