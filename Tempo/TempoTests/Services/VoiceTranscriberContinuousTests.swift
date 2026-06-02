//
// VoiceTranscriberContinuousTests.swift
// Tempo
//
// Replay test for continuous-mode transcript accumulation. Apple's speech
// recognizer rolls its internal segment over on long utterances —
// `formattedString` SILENTLY collapses to just the new segment, often with NO
// isFinal flag. Naively assigning `transcribedText = latestPartial` therefore
// loses everything before the last rollover (the device bug: a full pantry
// list reduced to "383 g of the one with the blackberry").
//
// These feed the EXACT partial stream captured from a real device session
// (2026-06-02, Nicola's fridge stock-take) through the pure accumulation
// logic and assert the assembled transcript retains every item across the
// rollovers. This converts "guess → build → device test → repeat" into a
// fast local loop.
//

@testable import Tempo
import XCTest

@MainActor
final class VoiceTranscriberContinuousTests: XCTestCase {

    /// Feed an ordered (partial, isFinal) stream through applyContinuousPartial,
    /// returning the final assembled transcript.
    private func replay(_ stream: [(String, Bool)]) -> String {
        let t = VoiceTranscriber()
        var assembled = ""
        for (partial, isFinal) in stream {
            assembled = t.applyContinuousPartial(partial, isFinal: isFinal)
        }
        return assembled
    }

    // MARK: - The real device stream (abridged to the load-bearing transitions)

    /// Captured from the device log. The growth within each segment is sampled
    /// (first, a mid point, and the last partial before each collapse) — the
    /// accumulator only cares about the segment BOUNDARIES, and sampling keeps
    /// the test readable while exercising the exact collapse fingerprints:
    ///   segment 1 peaks at 175 chars → collapses to "Two" (3)
    ///   segment 2 peaks at 338 chars → collapses to "Whatever" (8)
    ///   segment 3 peaks at 54 chars  → collapses to "Three" (5)
    ///   segment 4 grows to the final "383 g of the one with the blackberry"
    func testRealDeviceStream_retainsEveryItemAcrossRollovers() {
        // Verbatim device transcripts below; breaking them would obscure the
        // exact partial stream being replayed.
        // swiftlint:disable line_length
        let stream: [(String, Bool)] = [
            // Segment 1 — grows to ~175 chars.
            ("So I", false),
            ("Soap in the fridge is a piece of Parmesan cheese nice block", false),
            ("Soap in the fridge is a piece of Parmesan cheese nice block then I have two Land O Lakes salted butter the one with 56 g each I have three of them I have five eggs then I have", false),
            // ROLLOVER → segment 2 starts short.
            ("Two", false),
            ("Two low-fat ricotta cheese 50% more protein the one or 425 g then I have two lemon juice squeezed 206 ML", false),
            ("Two low-fat ricotta cheese 50% more protein the one or 425 g then I have two lemon juice squeezed 206 ML one and they're both full and 133 that one is close to the end then I have Kiko sauce sauce then I have two jams so I have the sugar-free with fiber seedless blackberry preserves and fresh raspberries raspberry preserves made with", false),
            // ROLLOVER → segment 3.
            ("Whatever", false),
            ("Whatever from Trader Joe's the 500 g the raspberry and", false),
            // ROLLOVER → segment 4 (numbers flutter, then settles).
            ("Three", false),
            ("383 g of the one with the blackberry", false),
            // User taps Stop → final.
            ("383 g of the one with the blackberry", true),
        ]
        // swiftlint:enable line_length

        let result = replay(stream)

        // Every spoken item must survive the rollovers.
        for item in [
            "Parmesan", "butter", "eggs", "ricotta", "lemon juice",
            "blackberry preserves", "raspberr", "Trader Joe's",
        ] {
            XCTAssertTrue(
                result.localizedCaseInsensitiveContains(item),
                "Assembled transcript dropped \"\(item)\" across a rollover.\nGot: \(result)"
            )
        }
    }

    // MARK: - Unit behaviors of the collapse heuristic

    func testNormalGrowth_staysOneSegment() {
        let result = replay([
            ("I have", false),
            ("I have rice", false),
            ("I have rice and pasta", false),
            ("I have rice and pasta and olive oil", true),
        ])
        XCTAssertEqual(result, "I have rice and pasta and olive oil",
                       "Monotonic growth must not bank intermediate segments")
    }

    func testRevisionFlutter_doesNotBank() {
        // Homophone/number revisions change length only slightly — must stay
        // in-segment, not trigger a rollover bank.
        let result = replay([
            ("then I have two lemon juice squeezed it hundred and", false), // 51
            ("then I have two lemon juice squeezed 200 and", false),        // 44 — minor drop
            ("then I have two lemon juice squeezed 206 ML", false),         // 43
            ("then I have two lemon juice squeezed 206 ML", true),
        ])
        XCTAssertEqual(result, "then I have two lemon juice squeezed 206 ML",
                       "Small revisions must not be treated as rollovers")
    }

    func testDramaticCollapse_banksPreviousSegment() {
        let result = replay([
            ("a long first segment with many words in it here", false), // 47
            ("Whatever", false), // 8 → <60% → rollover
            ("Whatever from the second segment", true),
        ])
        XCTAssertTrue(result.contains("long first segment"),
                      "A dramatic collapse must bank the first segment")
        XCTAssertTrue(result.contains("second segment"),
                      "...and keep the new one")
    }

    func testEmptyStream_isEmpty() {
        XCTAssertEqual(replay([]), "")
    }
}
