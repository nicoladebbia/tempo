//
// ProgressLabMathTests.swift
// Tempo
//
// §11.2 — pins the Strength Lab math: running-max PR flags (first session
// is always a PR, dips never are, a later new max is), span filtering
// measured back from now, and nearest-point scrub resolution.
//

@testable import Tempo
import XCTest

final class ProgressLabMathTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private var now: Date { Date(timeIntervalSince1970: 1_753_700_000) }

    private func point(daysAgo: Double, e1RM: Double?, volume: Double = 1000) -> ProgressLabMath.SessionPoint {
        ProgressLabMath.SessionPoint(
            date: now.addingTimeInterval(-daysAgo * day),
            e1RM: e1RM, volume: volume, bestWeight: 100, bestReps: 5
        )
    }

    func testRunningMaxPRFlags() {
        let series = ProgressLabMath.series(from: [
            point(daysAgo: 1, e1RM: 110), // new max → PR
            point(daysAgo: 30, e1RM: 100), // first → PR
            point(daysAgo: 20, e1RM: 95), // dip → not
            point(daysAgo: 10, e1RM: 100), // equals max → not
        ])
        XCTAssertEqual(series.map(\.isPR), [true, false, false, true])
        XCTAssertEqual(series.first?.e1RM, 100, "Series sorts ascending by date")
    }

    func testNilE1RMNeverPRs() {
        let series = ProgressLabMath.series(from: [
            point(daysAgo: 2, e1RM: nil),
            point(daysAgo: 1, e1RM: 90),
        ])
        XCTAssertEqual(series.map(\.isPR), [false, true])
    }

    func testSpanFilter() {
        let points = ProgressLabMath.series(from: [
            point(daysAgo: 5, e1RM: 100),
            point(daysAgo: 45, e1RM: 95),
            point(daysAgo: 200, e1RM: 90),
        ])
        XCTAssertEqual(ProgressLabMath.filter(points, span: .month, now: now).count, 1)
        XCTAssertEqual(ProgressLabMath.filter(points, span: .quarter, now: now).count, 2)
        XCTAssertEqual(ProgressLabMath.filter(points, span: .all, now: now).count, 3)
    }

    func testNearestPointForScrub() {
        let points = ProgressLabMath.series(from: [
            point(daysAgo: 10, e1RM: 100),
            point(daysAgo: 2, e1RM: 105),
        ])
        let hit = ProgressLabMath.nearest(
            to: now.addingTimeInterval(-3 * day), in: points
        )
        XCTAssertEqual(hit?.e1RM, 105, "Scrub snaps to the closest session")
        XCTAssertNil(ProgressLabMath.nearest(to: now, in: []))
    }
}
