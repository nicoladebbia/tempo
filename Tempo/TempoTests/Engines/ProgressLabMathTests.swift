//
// ProgressLabMathTests.swift
// Tempo
//
// §11.2 — pins the Strength Lab math: running-max PR flags (first session
// is the baseline, dips never are, a later new max is), same-day merge, span filtering
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
            point(daysAgo: 30, e1RM: 100), // first → baseline, not a PR
            point(daysAgo: 20, e1RM: 95), // dip → not
            point(daysAgo: 10, e1RM: 100), // equals max → not
        ])
        XCTAssertEqual(series.map(\.isPR), [false, false, false, true])
        XCTAssertEqual(series.first?.e1RM, 100, "Series sorts ascending by date")
    }

    func testNilE1RMNeverPRs() {
        let series = ProgressLabMath.series(from: [
            point(daysAgo: 2, e1RM: nil),
            point(daysAgo: 1, e1RM: 90),
            point(daysAgo: 0, e1RM: 95),
        ])
        XCTAssertEqual(series.map(\.isPR), [false, false, true])
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

    func testTwoSessionsOnOneDayMergeIntoOnePoint() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = Date(timeIntervalSince1970: 1_753_660_800 + 3600 * 8) // 08:00 UTC
        let evening = morning.addingTimeInterval(3600 * 8)
        let series = ProgressLabMath.series(from: [
            ProgressLabMath.SessionPoint(date: morning, e1RM: 100, volume: 1000, bestWeight: 80, bestReps: 8),
            ProgressLabMath.SessionPoint(date: evening, e1RM: 104, volume: 500, bestWeight: 90, bestReps: 3),
        ], calendar: calendar)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].e1RM, 104)
        XCTAssertEqual(series[0].volume, 1500)
        XCTAssertEqual(series[0].bestWeight, 90)
        XCTAssertEqual(series[0].bestReps, 3, "best set stays one real set")
    }

    func testDailyBestE1RMKeepsOnePositivePointPerDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let d0 = Date(timeIntervalSince1970: 1_753_660_800) // UTC midnight
        let days = ProgressLabMath.dailyBestE1RM([
            (d0.addingTimeInterval(3600), 100),
            (d0.addingTimeInterval(7200), 0), // bodyweight
            (d0.addingTimeInterval(9000), 103),
            (d0.addingTimeInterval(86_400 + 60), nil),
            (d0.addingTimeInterval(2 * 86_400), 98),
        ], calendar: calendar)
        XCTAssertEqual(days.map(\.e1RM), [103, 98])
    }
}
