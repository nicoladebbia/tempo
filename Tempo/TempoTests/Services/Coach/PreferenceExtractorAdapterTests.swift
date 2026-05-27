//
// PreferenceExtractorAdapterTests.swift
// Tempo
//
// Coach v2.1 Phase 8a — covers the JSON-array isolation + candidate
// parsing in the real extractor adapter. The network round-trip itself
// is exercised through CoachAdaptersTests' StubRequester pattern.
//

@testable import Tempo
import XCTest

final class PreferenceExtractorAdapterTests: XCTestCase {
    // MARK: - isolateJSONArray

    func testIsolate_unwrappedArrayReturnedVerbatim() {
        let raw = """
        [{"text":"x","subject":"tone.style","confidence":0.9,"source":"explicit","polarity":"positive","scope":"always","turnIndex":0,"evidence":"x"}]
        """
        XCTAssertEqual(PreferenceExtractorAdapter.isolateJSONArray(raw), raw)
    }

    func testIsolate_stripsMarkdownFence() {
        let raw = """
        ```json
        [{"text":"x","subject":"tone.style","confidence":0.9,"source":"explicit","polarity":"positive","scope":"always","turnIndex":null,"evidence":null}]
        ```
        """
        let result = PreferenceExtractorAdapter.isolateJSONArray(raw)
        XCTAssertTrue(result.hasPrefix("["))
        XCTAssertTrue(result.hasSuffix("]"))
    }

    func testIsolate_stripsLeadingPreamble() {
        let raw = """
        Here you go:
        [{"text":"x","subject":"tone.style","confidence":0.9,"source":"explicit","polarity":"positive","scope":"always","turnIndex":null,"evidence":null}]
        """
        let result = PreferenceExtractorAdapter.isolateJSONArray(raw)
        XCTAssertTrue(result.hasPrefix("["))
    }

    func testIsolate_handlesNoArray() {
        let raw = "no json here"
        XCTAssertEqual(PreferenceExtractorAdapter.isolateJSONArray(raw), raw)
    }

    // MARK: - parseCandidates

    func testParseCandidates_happyPath() throws {
        let raw = """
        [{"text":"user never eats before 11am","subject":"meal_timing.breakfast.skipped","confidence":0.9,"source":"explicit","polarity":"positive","scope":"always","turnIndex":2,"evidence":"I never eat before 11"}]
        """
        let candidates = PreferenceExtractorAdapter.parseCandidates(from: raw)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.subject, "meal_timing.breakfast.skipped")
        XCTAssertEqual(candidates.first?.source, .explicit)
        XCTAssertEqual(try XCTUnwrap(candidates.first?.confidence), 0.9, accuracy: 0.001)
    }

    func testParseCandidates_emptyOnGarbage() {
        XCTAssertEqual(
            PreferenceExtractorAdapter.parseCandidates(from: "not json").count,
            0
        )
    }

    func testParseCandidates_emptyArrayReturnsEmpty() {
        XCTAssertEqual(
            PreferenceExtractorAdapter.parseCandidates(from: "[]").count,
            0
        )
    }

    func testParseCandidates_skipsMalformedItem() {
        // Mixed array — one valid + one missing required fields.
        // Decoder gives up on the array as a whole (Codable doesn't
        // partial-decode); test documents that the adapter returns [] in
        // that case rather than silently dropping one item.
        let raw = """
        [
          {"text":"x","subject":"tone.style","confidence":0.9,"source":"explicit","polarity":"positive","scope":"always","turnIndex":null,"evidence":null},
          {"this":"isnt a candidate"}
        ]
        """
        let candidates = PreferenceExtractorAdapter.parseCandidates(from: raw)
        XCTAssertEqual(
            candidates.count, 0,
            "Codable fails the whole array on one bad item — documents the lossy-fallback behavior"
        )
    }
}
