//
// MobilityFlowTests.swift
// Tempo
//
// §10 mobility flows — sanity-pins the static flow data the guided player
// runs on: unique ids, non-empty moves with real how-to text, positive
// durations on timed moves (a 0s move would auto-advance instantly and make
// the player look broken).
//

@testable import Tempo
import XCTest

final class MobilityFlowTests: XCTestCase {
    func testFlowsAreNonEmptyWithUniqueIDs() {
        XCTAssertFalse(MobilityFlow.all.isEmpty)
        XCTAssertEqual(Set(MobilityFlow.all.map(\.id)).count, MobilityFlow.all.count,
                       "Flow ids must be unique — they drive sheet identity")
        for flow in MobilityFlow.all {
            XCTAssertFalse(flow.moves.isEmpty, "\(flow.name) has no moves")
        }
    }

    func testEveryMoveHasGuidanceAndSaneDuration() {
        for flow in MobilityFlow.all {
            for move in flow.moves {
                XCTAssertFalse(move.howTo.isEmpty, "\(flow.name)/\(move.name) missing how-to")
                if let secs = move.durationSeconds {
                    XCTAssertGreaterThan(secs, 0, "\(flow.name)/\(move.name) timed at 0s")
                }
            }
        }
    }

    func testEstimatedDurationIsDerivedFromMoves() {
        // Full-body reset: 60+90+60+60+90+90+60 = 510s ≈ 9 min.
        XCTAssertEqual(MobilityFlow.fullBodyReset.estimatedDuration, "~9 min")
    }
}
