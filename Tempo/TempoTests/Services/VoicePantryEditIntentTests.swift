//
// VoicePantryEditIntentTests.swift
// Tempo
//

@testable import Tempo
import XCTest

final class VoicePantryEditIntentTests: XCTestCase {
    // MARK: - markDepleted

    func testParse_imOutOf_producesMarkDepleted() {
        let intents = VoicePantryEditParser.parse("I'm out of rice")
        XCTAssertEqual(intents, [.markDepleted(rawName: "rice")])
    }

    func testParse_noMore_producesMarkDepleted() {
        let intents = VoicePantryEditParser.parse("no more milk")
        XCTAssertEqual(intents, [.markDepleted(rawName: "milk")])
    }

    func testParse_weReOutOf_producesMarkDepleted() {
        let intents = VoicePantryEditParser.parse("we're out of eggs")
        XCTAssertEqual(intents, [.markDepleted(rawName: "eggs")])
    }

    // MARK: - decrement

    func testParse_iUsedThe_producesFullDecrement() {
        let intents = VoicePantryEditParser.parse("I used the chicken")
        XCTAssertEqual(intents, [.decrement(rawName: "chicken", fraction: 1.0)])
    }

    func testParse_iUsedHalfThe_producesHalfDecrement() {
        let intents = VoicePantryEditParser.parse("I used half the rice")
        XCTAssertEqual(intents, [.decrement(rawName: "rice", fraction: 0.5)])
    }

    func testParse_iUsedUp_producesFullDecrement() {
        let intents = VoicePantryEditParser.parse("I used up the spinach")
        XCTAssertEqual(intents, [.decrement(rawName: "spinach", fraction: 1.0)])
    }

    func testParse_iUsedAllOfThe_producesFullDecrement() {
        let intents = VoicePantryEditParser.parse("I used all of the pasta")
        XCTAssertEqual(intents, [.decrement(rawName: "pasta", fraction: 1.0)])
    }

    // MARK: - move

    func testParse_moveToTheFreezer_producesMove() {
        let intents = VoicePantryEditParser.parse("move the chicken to the freezer")
        XCTAssertEqual(intents, [.move(rawName: "chicken", location: .freezer)])
    }

    func testParse_putInTheFridge_producesMove() {
        let intents = VoicePantryEditParser.parse("put the milk in the fridge")
        XCTAssertEqual(intents, [.move(rawName: "milk", location: .fridge)])
    }

    func testParse_moveToThePantry_producesMove() {
        let intents = VoicePantryEditParser.parse("move the flour to the pantry")
        XCTAssertEqual(intents, [.move(rawName: "flour", location: .pantry)])
    }

    // MARK: - discard

    func testParse_throwOutThe_producesDiscard() {
        let intents = VoicePantryEditParser.parse("throw out the spinach")
        XCTAssertEqual(intents, [.discard(rawName: "spinach")])
    }

    func testParse_tossThe_producesDiscard() {
        let intents = VoicePantryEditParser.parse("toss the moldy bread")
        XCTAssertEqual(intents, [.discard(rawName: "moldy bread")])
    }

    // MARK: - Multi-clause splitting

    func testParse_multipleClausesJoinedByAnd_producesMultipleIntents() {
        let intents = VoicePantryEditParser.parse("I'm out of rice and move the chicken to the freezer")
        XCTAssertEqual(intents, [
            .markDepleted(rawName: "rice"),
            .move(rawName: "chicken", location: .freezer),
        ])
    }

    func testParse_clausesJoinedByCommaAnd_producesMultipleIntents() {
        let intents = VoicePantryEditParser.parse("throw out the spinach, and I used the milk")
        XCTAssertEqual(intents, [
            .discard(rawName: "spinach"),
            .decrement(rawName: "milk", fraction: 1.0),
        ])
    }

    func testParse_clausesSeparatedByPeriod_producesMultipleIntents() {
        let intents = VoicePantryEditParser.parse("I'm out of eggs. I used half the rice.")
        XCTAssertEqual(intents, [
            .markDepleted(rawName: "eggs"),
            .decrement(rawName: "rice", fraction: 0.5),
        ])
    }

    // MARK: - Unrecognized clauses dropped

    func testParse_unrecognizedClause_isDropped() {
        let intents = VoicePantryEditParser.parse("the weather is nice today")
        XCTAssertTrue(intents.isEmpty)
    }

    func testParse_mixOfRecognizedAndUnrecognized_keepsOnlyRecognized() {
        let intents = VoicePantryEditParser.parse("the weather is nice and I'm out of rice")
        XCTAssertEqual(intents, [.markDepleted(rawName: "rice")])
    }

    func testParse_emptyTranscript_returnsEmpty() {
        XCTAssertTrue(VoicePantryEditParser.parse("").isEmpty)
    }

    // MARK: - Case insensitivity

    func testParse_isCaseInsensitive() {
        let intents = VoicePantryEditParser.parse("I'M OUT OF RICE")
        XCTAssertEqual(intents, [.markDepleted(rawName: "rice")])
    }
}
