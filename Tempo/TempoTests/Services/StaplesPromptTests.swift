//
// StaplesPromptTests.swift
// Tempo
//
// Staples prompt state machine + persistence, and allergy/diet filtering of
// the staple suggestions.
//

import Foundation
@testable import Tempo
import XCTest

final class StaplesPromptTests: XCTestCase {
    private func store() -> StaplesPromptStore {
        let suite = "staples.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return StaplesPromptStore(defaults: defaults)
    }

    // MARK: State machine

    func testStartsOfferedAndShowsPeek() {
        let machine = StaplesPromptMachine()
        XCTAssertEqual(machine.phase, .offered)
        XCTAssertTrue(machine.showsPeekCard)
    }

    func testSkipHidesPeekAndSurvivesReopen() {
        var machine = StaplesPromptMachine()
        machine.apply(.skip)
        XCTAssertEqual(machine.phase, .skipped)
        XCTAssertFalse(machine.showsPeekCard)
        machine.apply(.reopen)
        XCTAssertEqual(machine.phase, .skipped, "reopening from the chip changes nothing")
    }

    func testCompleteIsFinalAndSkipCannotUndoIt() {
        var machine = StaplesPromptMachine()
        machine.apply(.complete)
        XCTAssertEqual(machine.phase, .done)
        machine.apply(.skip)
        XCTAssertEqual(machine.phase, .done)
        var skipped = StaplesPromptMachine(phase: .skipped)
        skipped.apply(.complete)
        XCTAssertEqual(skipped.phase, .done)
    }

    func testPersistence() {
        let s = store()
        XCTAssertEqual(s.machine.phase, .offered)
        XCTAssertFalse(s.hasStoredPhase)
        var m = s.machine
        m.apply(.skip)
        s.machine = m
        XCTAssertEqual(s.machine.phase, .skipped)
        XCTAssertTrue(s.hasStoredPhase)
        s.declined = ["honey", "salt"]
        XCTAssertEqual(s.declined, ["honey", "salt"])
    }

    // MARK: Diet filtering

    private func names(_ filter: StapleDietFilter) -> Set<String> {
        Set(PantryStaple.suggestions(for: filter).map(\.canonicalName))
    }

    func testNoFilterKeepsEverything() {
        XCTAssertEqual(PantryStaple.suggestions(for: .none).count, PantryStaple.commonSuggestions.count)
    }

    func testSoyAllergyDropsSoyAndSoyOil() {
        let result = names(StapleDietFilter(avoidTerms: ["Soy"]))
        XCTAssertFalse(result.contains("soy sauce"))
        XCTAssertFalse(result.contains("vegetable oil"))
        XCTAssertTrue(result.contains("salt"))
        XCTAssertTrue(result.contains("honey"), "soy allergy alone keeps honey")
    }

    func testAvoidingAddedSugarsDropsHoneyAndSugar() {
        let result = names(StapleDietFilter(avoidAddedSugars: true))
        XCTAssertFalse(result.contains("honey"))
        XCTAssertFalse(result.contains("sugar"))
        XCTAssertFalse(result.contains("brown sugar"))
        XCTAssertTrue(result.contains("olive oil"))
    }

    func testGlutenFreeAndVegan() {
        let gf = names(StapleDietFilter(glutenFree: true))
        XCTAssertFalse(gf.contains("flour"))
        XCTAssertFalse(gf.contains("soy sauce"))
        let vegan = names(StapleDietFilter(vegan: true))
        XCTAssertFalse(vegan.contains("honey"))
        XCTAssertFalse(vegan.contains("mayonnaise"))
    }

    func testWontEatTermsMatchWholeWords() {
        XCTAssertFalse(names(StapleDietFilter(avoidTerms: ["mustard"])).contains("mustard"))
        XCTAssertFalse(names(StapleDietFilter(avoidTerms: ["egg"])).contains("mayonnaise"))
        // a bell-pepper dislike must not hide black pepper
        XCTAssertTrue(names(StapleDietFilter(avoidTerms: ["bell pepper"])).contains("black pepper"))
    }
}
