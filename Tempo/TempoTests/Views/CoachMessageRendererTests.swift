//
// CoachMessageRendererTests.swift
// Tempo
//
// Coach v2.1 Phase 7b — covers the citation-marker stripping + extraction
// helpers used by CoachChatView. Visual rendering itself is verified
// by build-green + the morning manual-QA pass.
//

@testable import Tempo
import XCTest

final class CoachMessageRendererTests: XCTestCase {
    // MARK: - strippingCitationMarkers

    func testStripping_removesSingleMarker() {
        let input = "You should eat dinner by 9:30. [pref_a3f1]"
        let output = CoachMessageRenderer.strippingCitationMarkers(input)
        XCTAssertEqual(output, "You should eat dinner by 9:30.")
    }

    func testStripping_removesMultipleMarkersInline() {
        let input = "Move dinner earlier [pref_a3f1] and swap tomorrow [pref_c84a]."
        let output = CoachMessageRenderer.strippingCitationMarkers(input)
        XCTAssertEqual(output, "Move dinner earlier and swap tomorrow.")
    }

    func testStripping_keepsTextWithoutMarkers() {
        let input = "Plain text with no markers."
        XCTAssertEqual(
            CoachMessageRenderer.strippingCitationMarkers(input),
            input
        )
    }

    func testStripping_emptyString() {
        XCTAssertEqual(
            CoachMessageRenderer.strippingCitationMarkers(""),
            ""
        )
    }

    func testStripping_leavesNonCitationBracketsAlone() {
        let input = "Eat at 19:30 [post-workout] [pref_a3f1]."
        let output = CoachMessageRenderer.strippingCitationMarkers(input)
        XCTAssertEqual(output, "Eat at 19:30 [post-workout].")
    }

    func testStripping_ignoresNonHexContent() {
        // Non-hex chars after pref_ shouldn't match.
        let input = "X [pref_zzzz] Y"
        XCTAssertEqual(
            CoachMessageRenderer.strippingCitationMarkers(input),
            "X [pref_zzzz] Y"
        )
    }

    // MARK: - citedPreferenceShortIDs

    func testExtraction_returnsAllShortIDs() {
        let text = "Hello [pref_a3f1] world [pref_c84a]."
        XCTAssertEqual(
            CoachMessageRenderer.citedPreferenceShortIDs(in: text),
            ["a3f1", "c84a"]
        )
    }

    func testExtraction_emptyWhenNoMarkers() {
        XCTAssertEqual(
            CoachMessageRenderer.citedPreferenceShortIDs(in: "plain text"),
            []
        )
    }

    func testExtraction_handlesDuplicates() {
        // Same marker twice should appear twice — let the caller dedupe
        // if they want unique citations.
        let text = "[pref_a3f1] and [pref_a3f1]"
        XCTAssertEqual(
            CoachMessageRenderer.citedPreferenceShortIDs(in: text),
            ["a3f1", "a3f1"]
        )
    }

    func testExtraction_ignoresMalformedMarkers() {
        // pref_ without brackets, brackets without pref_, non-hex chars.
        let text = "[notpref_xx] [pref_ABCD] pref_a3f1 [pref_g123] [pref_aa]"
        // Uppercase + g are non-[a-f0-9] → only "aa" matches.
        XCTAssertEqual(
            CoachMessageRenderer.citedPreferenceShortIDs(in: text),
            ["aa"]
        )
    }
}
