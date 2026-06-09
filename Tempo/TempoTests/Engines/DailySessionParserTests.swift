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

    func testTooLongShortWhyThrows() {
        let long = String(repeating: "x", count: 121)
        let json = """
        {"modality":"rest","intensity":"recovery","durationMin":20,
         "blocks":[{"kind":"mobility","label":"Stretch"}],"shortWhy":"\(long)"}
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
