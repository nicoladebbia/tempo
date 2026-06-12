//
// MorningCheckInTests.swift
// Tempo
//
// Guards the two silent-failure seams on the check-in (advisor):
//   1. sorenessRaw (JSON String) ↔ soreness ([String:Int]) round-trips; malformed
//      / empty / nil → [:], never a crash.
//   2. The 1–10 soreness scale agrees with MorningCheckInSnapshot.painFlags (>= 8),
//      so §15.5 pain-routing actually fires. A 1–5 card scale would silently kill it.
//

@testable import Tempo
import XCTest

final class MorningCheckInTests: XCTestCase {

    func testSorenessRoundTrips() {
        let ci = MorningCheckIn(date: Date(), mood: 4, stress: 3, soreness: ["knee": 9, "quads": 5])
        // Persisted as JSON…
        XCTAssertNotNil(ci.sorenessRaw)
        // …and decodes back to the same dict.
        XCTAssertEqual(ci.soreness, ["knee": 9, "quads": 5])
    }

    func testEmptySorenessIsNilRaw() {
        let ci = MorningCheckIn(date: Date(), soreness: [:])
        XCTAssertNil(ci.sorenessRaw, "Empty soreness → nil raw, not '{}' noise")
        XCTAssertEqual(ci.soreness, [:])
    }

    func testMalformedSorenessDecodesToEmptyNotCrash() {
        XCTAssertEqual(MorningCheckIn.decodeSoreness("not json"), [:])
        XCTAssertEqual(MorningCheckIn.decodeSoreness(nil), [:])
        XCTAssertEqual(MorningCheckIn.decodeSoreness(""), [:])
    }

    func testSorenessSetterReencodes() {
        let ci = MorningCheckIn(date: Date())
        ci.soreness = ["hamstring": 8]
        XCTAssertEqual(ci.soreness, ["hamstring": 8])
        XCTAssertNotNil(ci.sorenessRaw)
    }

    // MARK: - The scale-agreement contract (§15.5 pain routing)

    func testPainFlagsFireAtEightOnTenScale() {
        // A value of 8 on the 1–10 scale MUST register as a pain flag, or §15.5
        // pain-routing silently dies. This binds the card scale to the snapshot.
        let ci = MorningCheckIn(date: Date(), soreness: ["knee": 8, "calf": 7])
        let snap = ci.snapshot
        XCTAssertEqual(snap.painFlags, ["knee"], "8/10 = pain flag; 7/10 = not")
    }

    func testNoPainFlagsBelowThreshold() {
        let ci = MorningCheckIn(date: Date(), soreness: ["quads": 5, "glutes": 6])
        XCTAssertTrue(ci.snapshot.painFlags.isEmpty)
    }

    func testSnapshotCarriesMoodAndStress() {
        let ci = MorningCheckIn(date: Date(), mood: 2, stress: 9)
        XCTAssertEqual(ci.snapshot.mood, 2)
        XCTAssertEqual(ci.snapshot.stress, 9)
    }

    func testDateNormalizedToStartOfDay() {
        let noon = Date(timeIntervalSince1970: 1_700_000_000 + 43_200)
        let ci = MorningCheckIn(date: noon)
        XCTAssertEqual(ci.date, Calendar.current.startOfDay(for: noon))
    }
}
