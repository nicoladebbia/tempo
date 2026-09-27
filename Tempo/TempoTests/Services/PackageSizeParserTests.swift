//
// PackageSizeParserTests.swift
// Tempo
//

@testable import Tempo
import XCTest

final class PackageSizeParserTests: XCTestCase {
    func testParse_grams() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("500 g"))
        XCTAssertEqual(result.quantity, 500)
        XCTAssertEqual(result.unit, .grams)
    }

    func testParse_gramsNoSpace() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("500g"))
        XCTAssertEqual(result.quantity, 500)
        XCTAssertEqual(result.unit, .grams)
    }

    func testParse_kilograms() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("1 kg"))
        XCTAssertEqual(result.quantity, 1)
        XCTAssertEqual(result.unit, .kilograms)
    }

    func testParse_liters() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("1 L"))
        XCTAssertEqual(result.quantity, 1)
        XCTAssertEqual(result.unit, .liters)
    }

    func testParse_milliliters() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("330 ml"))
        XCTAssertEqual(result.quantity, 330)
        XCTAssertEqual(result.unit, .milliliters)
    }

    func testParse_centiliters_convertsToMilliliters() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("33 cl"))
        XCTAssertEqual(result.quantity, 330)
        XCTAssertEqual(result.unit, .milliliters)
    }

    func testParse_milligrams_convertsToGrams() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("500 mg"))
        XCTAssertEqual(result.quantity, 0.5)
        XCTAssertEqual(result.unit, .grams)
    }

    func testParse_ounces() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("12 oz"))
        XCTAssertEqual(result.quantity, 12)
        XCTAssertEqual(result.unit, .ounces)
    }

    func testParse_pounds() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("2 lb"))
        XCTAssertEqual(result.quantity, 2)
        XCTAssertEqual(result.unit, .pounds)
    }

    func testParse_multipack_xNotation() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("6 x 33 cl"))
        XCTAssertEqual(result.quantity, 1980, accuracy: 0.001) // 6 * 330 ml
        XCTAssertEqual(result.unit, .milliliters)
    }

    func testParse_multipack_timesSymbol() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("4 × 125g"))
        XCTAssertEqual(result.quantity, 500, accuracy: 0.001)
        XCTAssertEqual(result.unit, .grams)
    }

    func testParse_commaDecimalSeparator() throws {
        let result = try XCTUnwrap(PackageSizeParser.parse("1,5 kg"))
        XCTAssertEqual(result.quantity, 1.5, accuracy: 0.001)
        XCTAssertEqual(result.unit, .kilograms)
    }

    func testParse_nilLabel_returnsNil() {
        XCTAssertNil(PackageSizeParser.parse(nil))
    }

    func testParse_emptyLabel_returnsNil() {
        XCTAssertNil(PackageSizeParser.parse(""))
    }

    func testParse_unparseableLabel_returnsNil() {
        XCTAssertNil(PackageSizeParser.parse("family size"))
    }
}
