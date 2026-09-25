//
// SideRepsFormatTests.swift
// Tempo
//
// Fix #9 — shared "N / side" copy used by Today, the active workout, the
// summary and history.
//

@testable import Tempo
import XCTest

final class SideRepsFormatTests: XCTestCase {
    func testRepsPlainWhenNotPerSide() {
        XCTAssertEqual(SideRepsFormat.reps(8, perSide: false), "8")
    }

    func testRepsAppendsPerSideSuffix() {
        XCTAssertEqual(SideRepsFormat.reps(8, perSide: true), "8 / side")
    }

    func testLoggedRepsPlainWhenNotPerSide() {
        XCTAssertEqual(SideRepsFormat.loggedReps(actual: 8, left: nil, right: nil, perSide: false), "8")
    }

    func testLoggedRepsShowsPerSideWhenBothSidesMatched() {
        XCTAssertEqual(SideRepsFormat.loggedReps(actual: 8, left: nil, right: nil, perSide: true), "8 / side")
        XCTAssertEqual(SideRepsFormat.loggedReps(actual: 8, left: 8, right: 8, perSide: true), "8 / side")
    }

    func testLoggedRepsShowsUnevenSplit() {
        XCTAssertEqual(SideRepsFormat.loggedReps(actual: 8, left: 8, right: 7, perSide: true), "L 8 / R 7")
    }

    func testLoadAddsPerHandOnlyForDumbbellOrKettlebellPerSide() {
        XCTAssertEqual(SideRepsFormat.load("20kg", perSide: true, equipment: .dumbbell), "20kg / hand")
        XCTAssertEqual(SideRepsFormat.load("20kg", perSide: true, equipment: .kettlebell), "20kg / hand")
        XCTAssertEqual(SideRepsFormat.load("20kg", perSide: true, equipment: .barbell), "20kg")
        XCTAssertEqual(SideRepsFormat.load("20kg", perSide: false, equipment: .dumbbell), "20kg")
    }
}
