//
// GuidedRunCuePhraseBuilderTests.swift
// Tempo
//
// Guided run mode — voice cue phrase selection, EN and IT, including the
// under/over-cap wording and the "last rep" special case.
//

@testable import Tempo
import XCTest

final class GuidedRunCuePhraseBuilderTests: XCTestCase {
    // MARK: - English

    func testCountdownAndGo() {
        XCTAssertEqual(GuidedRunCuePhraseBuilder.phrase(for: .countdown(3), isItalian: false), "3")
        XCTAssertEqual(GuidedRunCuePhraseBuilder.phrase(for: .go, isItalian: false), "Go")
    }

    func testRepStartWithCap() {
        let phrase = GuidedRunCuePhraseBuilder.phrase(
            for: .repStart(index: 1, of: 4, capSeconds: 65, isLast: false),
            isItalian: false
        )
        XCTAssertEqual(phrase, "Rep 2 of 4 — cap 1:05")
    }

    func testRepStartWithoutCap() {
        let phrase = GuidedRunCuePhraseBuilder.phrase(
            for: .repStart(index: 0, of: 2, capSeconds: nil, isLast: false),
            isItalian: false
        )
        XCTAssertEqual(phrase, "Rep 1 of 2")
    }

    func testLastRepOmitsTheCount() {
        let phrase = GuidedRunCuePhraseBuilder.phrase(
            for: .repStart(index: 3, of: 4, capSeconds: 65, isLast: true),
            isItalian: false
        )
        XCTAssertEqual(phrase, "Last rep — cap 1:05")
    }

    func testUnderCapPhrase() {
        let phrase = GuidedRunCuePhraseBuilder.phrase(
            for: .repResult(elapsedSeconds: 58, capSeconds: 65),
            isItalian: false
        )
        XCTAssertEqual(phrase, "Under the cap — 58 seconds. Nice.")
    }

    func testOverCapPhrase() {
        let phrase = GuidedRunCuePhraseBuilder.phrase(
            for: .repResult(elapsedSeconds: 68, capSeconds: 65),
            isItalian: false
        )
        XCTAssertEqual(phrase, "Over — 1:08. Push the next one.")
    }

    func testRepResultWithNoCapIsJustTheTime() {
        let phrase = GuidedRunCuePhraseBuilder.phrase(
            for: .repResult(elapsedSeconds: 12, capSeconds: nil),
            isItalian: false
        )
        XCTAssertEqual(phrase, "12 seconds")
    }

    func testIsOverCap() {
        XCTAssertTrue(GuidedRunCuePhraseBuilder.isOverCap(.repResult(elapsedSeconds: 68, capSeconds: 65)))
        XCTAssertFalse(GuidedRunCuePhraseBuilder.isOverCap(.repResult(elapsedSeconds: 58, capSeconds: 65)))
        XCTAssertFalse(GuidedRunCuePhraseBuilder.isOverCap(.repResult(elapsedSeconds: 58, capSeconds: nil)))
        XCTAssertFalse(GuidedRunCuePhraseBuilder.isOverCap(.go))
    }

    func testTenSecondsAndHalfwayAndDone() {
        XCTAssertEqual(GuidedRunCuePhraseBuilder.phrase(for: .tenSecondsLeft, isItalian: false), "Ten seconds")
        XCTAssertEqual(GuidedRunCuePhraseBuilder.phrase(for: .halfway, isItalian: false), "Halfway")
        XCTAssertEqual(GuidedRunCuePhraseBuilder.phrase(for: .done, isItalian: false), "Done. Session complete.")
    }

    // MARK: - Italian

    func testItalianGoAndRest() {
        XCTAssertEqual(GuidedRunCuePhraseBuilder.phrase(for: .go, isItalian: true), "Via")
        XCTAssertEqual(GuidedRunCuePhraseBuilder.phrase(for: .restStart, isItalian: true), "Recupero")
    }

    func testItalianRepStartAndLastRep() {
        XCTAssertEqual(
            GuidedRunCuePhraseBuilder.phrase(for: .repStart(index: 1, of: 4, capSeconds: 65, isLast: false), isItalian: true),
            "Rep 2 di 4, cap 1:05"
        )
        XCTAssertEqual(
            GuidedRunCuePhraseBuilder.phrase(for: .repStart(index: 3, of: 4, capSeconds: 65, isLast: true), isItalian: true),
            "Ultima rep, cap 1:05"
        )
    }

    func testItalianUnderAndOverCap() {
        XCTAssertEqual(
            GuidedRunCuePhraseBuilder.phrase(for: .repResult(elapsedSeconds: 58, capSeconds: 65), isItalian: true),
            "Sotto il cap — 58 seconds. Bene."
        )
        XCTAssertEqual(
            GuidedRunCuePhraseBuilder.phrase(for: .repResult(elapsedSeconds: 68, capSeconds: 65), isItalian: true),
            "Sopra il cap — 1:08. Spingi la prossima."
        )
    }
}
