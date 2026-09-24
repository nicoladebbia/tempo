//
// TrainerProgramPageTranscriberTests.swift
// Tempo
//
// Pins the TRANSCRIBE step's prompt contract — no network. The vision call
// itself (TrainerProgramPageTranscriber.transcribe) needs a real proxy
// response and isn't covered here; only the pure prompt builder is.
//

@testable import Tempo
import XCTest

final class TrainerProgramPageTranscriberTests: XCTestCase {
    func testUserMessageAsksForRowByRowTranscription() {
        let message = TrainerProgramPageTranscriber.userMessage(hintText: nil)
        XCTAssertTrue(message.contains("row by row"))
        XCTAssertTrue(message.contains("A | Leg Press | 3 x 8"))
    }

    func testUserMessageWithNilHintOmitsHintBlock() {
        let message = TrainerProgramPageTranscriber.userMessage(hintText: nil)
        XCTAssertFalse(message.contains("<hint>"))
    }

    func testUserMessageWithBlankHintOmitsHintBlock() {
        let message = TrainerProgramPageTranscriber.userMessage(hintText: "   \n  ")
        XCTAssertFalse(message.contains("<hint>"))
    }

    func testUserMessageIncludesHintTextVerbatim() {
        let hint = "A Leg Press 3 x 8 70%"
        let message = TrainerProgramPageTranscriber.userMessage(hintText: hint)
        XCTAssertTrue(message.contains("<hint>"))
        XCTAssertTrue(message.contains(hint))
        XCTAssertTrue(message.contains("</hint>"))
    }

    func testUserMessageTruncatesAnOverlongHint() {
        let hint = String(repeating: "x", count: 5000)
        let message = TrainerProgramPageTranscriber.userMessage(hintText: hint)
        // The hint is capped to 4000 chars — the message shouldn't carry
        // all 5000 repeated characters.
        XCTAssertLessThan(message.count, hint.count + 500)
    }

    func testSystemPromptDoesNotAskToStructureOrTranslate() {
        XCTAssertTrue(TrainerProgramPageTranscriber.systemPrompt.contains("do not structure"))
    }
}
