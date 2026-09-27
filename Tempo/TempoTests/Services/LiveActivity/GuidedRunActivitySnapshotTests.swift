//
// GuidedRunActivitySnapshotTests.swift
// Tempo
//
// Guided run mode — the Watch message encode/decode round trip for the
// snapshot fanned out to the Live Activity and the wrist mirror
// (`toDictionary()`/`from(dictionary:)`, the same wire shape
// `PhoneWatchConnectivityService.pushGuidedRun` sends over WCSession and
// `WatchConnectivityService.ingestGuidedRun` reads back on the watch).
//

@testable import Tempo
import XCTest

final class GuidedRunActivitySnapshotTests: XCTestCase {
    private func makeSnapshot() -> GuidedRunActivitySnapshot {
        GuidedRunActivitySnapshot(
            stepTitle: "Shuttle · Rep 2/4",
            detailText: "Cap 1:05",
            nextStepText: "Next: Rep 3/4",
            distanceText: "1.20 km",
            paceText: "5:12/km",
            heartRateText: "142 bpm",
            heartRateZone: 3,
            isRest: false,
            isCountdown: false,
            isPaused: false,
            countsDown: false,
            timerAnchor: Date(timeIntervalSince1970: 1_700_000_000),
            frozenText: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_005)
        )
    }

    func testRoundTripThroughDictionaryPreservesEveryField() throws {
        let original = makeSnapshot()
        let dict = original.toDictionary()
        let decoded = try XCTUnwrap(GuidedRunActivitySnapshot.from(dictionary: dict))
        XCTAssertEqual(decoded, original)
    }

    func testRoundTripWithNilOptionalFields() throws {
        var snapshot = makeSnapshot()
        snapshot.detailText = nil
        snapshot.nextStepText = nil
        snapshot.distanceText = nil
        snapshot.paceText = nil
        snapshot.heartRateText = nil
        snapshot.heartRateZone = nil
        snapshot.frozenText = nil

        let dict = snapshot.toDictionary()
        let decoded = try XCTUnwrap(GuidedRunActivitySnapshot.from(dictionary: dict))
        XCTAssertEqual(decoded, snapshot)
    }

    func testFromDictionaryReturnsNilForGarbageInput() {
        XCTAssertNil(GuidedRunActivitySnapshot.from(dictionary: ["nonsense": "value"]))
        XCTAssertNil(GuidedRunActivitySnapshot.from(dictionary: [:]))
    }

    /// The wire dictionary is keyed under `contextKey` when sent as part of
    /// a WCSession message/application context alongside other payloads
    /// (`WatchSnapshot`, `WatchWorkoutPayload`) — this is the shape
    /// `ingestGuidedRun` actually parses.
    func testContextKeyWrappedDictionaryRoundTrips() throws {
        let original = makeSnapshot()
        let wrapped: [String: Any] = [GuidedRunActivitySnapshot.contextKey: original.toDictionary()]

        let raw = try XCTUnwrap(wrapped[GuidedRunActivitySnapshot.contextKey] as? [String: Any])
        let decoded = try XCTUnwrap(GuidedRunActivitySnapshot.from(dictionary: raw))
        XCTAssertEqual(decoded, original)
    }
}
