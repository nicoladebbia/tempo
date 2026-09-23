//
// UniversityDirectoryTests.swift
// Tempo
//
// Onboarding school picker search: ranking, acronyms, diacritics, and that
// the bundled Universities.json actually ships in the app.
//

@testable import Tempo
import XCTest

final class UniversityDirectoryTests: XCTestCase {
    private let directory = UniversityDirectory(universities: [
        University(name: "Florida International University", countryCode: "US"),
        University(name: "Florida State University", countryCode: "US"),
        University(name: "University of Florida", countryCode: "US"),
        University(name: "Florida Institute of Technology", countryCode: "US"),
        University(name: "Universität Zürich", countryCode: "CH"),
        University(name: "Università di Bologna", countryCode: "IT"),
        University(name: "University of Bologna Residential Center", countryCode: "AR"),
    ])

    func testPrefixMatchesRankBeforeSubstringMatches() {
        let names = directory.search("florida").map(\.name)
        XCTAssertEqual(names.last, "University of Florida")
        XCTAssertEqual(names.count, 4)
    }

    func testAcronymFindsSchool() {
        XCTAssertEqual(directory.search("FIU").first?.name, "Florida International University")
        XCTAssertEqual(directory.search("fsu").first?.name, "Florida State University")
    }

    func testMultiWordQueryMatchesWordPrefixesInAnyOrder() {
        XCTAssertEqual(directory.search("intl flor").map(\.name), [])
        XCTAssertEqual(directory.search("inter flor").first?.name, "Florida International University")
    }

    func testDiacriticAndCaseInsensitive() {
        XCTAssertEqual(directory.search("universitat zurich").first?.name, "Universität Zürich")
    }

    func testPreferredCountryBreaksTies() {
        let italyFirst = directory.search("bologna", preferredCountryCode: "IT")
        XCTAssertEqual(italyFirst.first?.countryCode, "IT")
        let argentinaFirst = directory.search("bologna", preferredCountryCode: "AR")
        XCTAssertEqual(argentinaFirst.first?.countryCode, "AR")
    }

    func testShortQueriesAndLimit() {
        XCTAssertTrue(directory.search("f").isEmpty)
        XCTAssertTrue(directory.search("  ").isEmpty)
        XCTAssertEqual(directory.search("univ", limit: 2).count, 2)
    }

    func testBundledDirectoryLoads() {
        let fiu = UniversityDirectory.shared.search("Florida International University")
        XCTAssertEqual(fiu.first?.name, "Florida International University")
        XCTAssertEqual(fiu.first?.countryCode, "US")
    }
}
