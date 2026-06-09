//
// DailySessionParserTests.swift
// Tempo
//
// Proves the §13.1 per-kind contract parser: valid sessions parse, contract
// violations throw (→ deterministic-floor fallback, never half-parsed), and the
// extractor tolerates Haiku's ```json fences / prose preamble. Pure.
//

@testable import Tempo
import XCTest

final class DailySessionParserTests: XCTestCase {

    private typealias P = DailySessionParser

    func testCleanGymPointerParses() throws {
        let json = """
        {"modality":"legs","intensity":"hard","durationMin":70,
         "blocks":[{"kind":"gym","label":"Legs","split":"legs","cue":"Brace."}],
         "shortWhy":"Green light.","expectedSessionRPE":8}
        """
        let s = try P.parse(json)
        XCTAssertEqual(s.modality, "legs")
        XCTAssertEqual(s.blocks.first?.split, "legs")
    }

    func testFencedJSONWithPreambleParses() throws {
        let raw = """
        Here's today's session:
        ```json
        {"modality":"run","intensity":"easy","durationMin":30,
         "blocks":[{"kind":"run","label":"Easy run","runType":"tempo","distanceM":5000}],
         "shortWhy":"Aerobic base."}
        ```
        """
        let s = try P.parse(raw)
        XCTAssertEqual(s.modality, "run")
    }

    func testGymWithoutSplitThrows() {
        let json = """
        {"modality":"legs","intensity":"hard","durationMin":70,
         "blocks":[{"kind":"gym","label":"Legs"}],"shortWhy":"x"}
        """
        XCTAssertThrowsError(try P.parse(json)) { err in
            guard case DailySessionParseError.blockContractViolated(.gym, "split") = err else {
                return XCTFail("Expected gym/split violation, got \(err)")
            }
        }
    }

    func testRunWithoutDistanceOrDurationThrows() {
        let json = """
        {"modality":"run","intensity":"easy","durationMin":30,
         "blocks":[{"kind":"run","label":"Run","runType":"tempo"}],"shortWhy":"x"}
        """
        XCTAssertThrowsError(try P.parse(json))
    }

    func testEmptyBlocksThrows() {
        let json = #"{"modality":"rest","intensity":"recovery","durationMin":0,"blocks":[],"shortWhy":"x"}"#
        XCTAssertThrowsError(try P.parse(json)) { err in
            guard case DailySessionParseError.emptyBlocks = err else {
                return XCTFail("Expected emptyBlocks, got \(err)")
            }
        }
    }

    func testModeratelyLongShortWhySurvivesInFull() throws {
        // A 130-char shortWhy is a COMPLETE, correct session — and it renders
        // IN FULL: the card wraps, and a mid-word "…" cut reads worse than an
        // extra line (live complaint 2026-06-09: "Preserve progres…"). The
        // ≤120 ask stays in the prompt; the parser no longer enforces it.
        let long = String(repeating: "x", count: 130)
        let json = """
        {"modality":"pull","intensity":"moderate","durationMin":50,
         "blocks":[{"kind":"gym","label":"Pull","split":"pull"}],"shortWhy":"\(long)"}
        """
        let s = try P.parse(json)
        XCTAssertEqual(s.shortWhy, long, "Moderate overrun passes through verbatim — whole words, no ellipsis")
        XCTAssertEqual(s.modality, "pull", "The rest of the session survives intact")
    }

    func testPathologicalShortWhyIsWordCutNotMidWord() throws {
        // Past the 240 display cap (the model dumped fullWhy-sized prose into
        // the title) we still cut — but at a WORD boundary, never mid-word.
        let long = Array(repeating: "alpha", count: 60).joined(separator: " ") // 359 chars
        let json = """
        {"modality":"pull","intensity":"moderate","durationMin":50,
         "blocks":[{"kind":"gym","label":"Pull","split":"pull"}],"shortWhy":"\(long)"}
        """
        let s = try P.parse(json)
        XCTAssertLessThanOrEqual(s.shortWhy.count, P.shortWhyDisplayCap, "Cut to the display cap")
        XCTAssertTrue(s.shortWhy.hasSuffix("alpha…"), "Cut lands after a whole word, ellipsis-marked")
    }

    func testEmptyShortWhyStillThrows() {
        // Empty = the model gave NO rationale = structural, still hard-fails.
        let json = """
        {"modality":"rest","intensity":"recovery","durationMin":20,
         "blocks":[{"kind":"mobility","label":"Stretch"}],"shortWhy":""}
        """
        XCTAssertThrowsError(try P.parse(json))
    }

    func testGarbageThrowsNotValidJSON() {
        XCTAssertThrowsError(try P.parse("the model refused to answer")) { err in
            guard case DailySessionParseError.notValidJSON = err else {
                return XCTFail("Expected notValidJSON, got \(err)")
            }
        }
    }

    func testMobilityNeedsNoExtraFields() throws {
        let json = """
        {"modality":"rest","intensity":"recovery","durationMin":20,
         "blocks":[{"kind":"mobility","label":"Mobility flow"}],"shortWhy":"Recover."}
        """
        let s = try P.parse(json)
        XCTAssertEqual(s.blocks.first?.kind, .mobility)
    }
}
