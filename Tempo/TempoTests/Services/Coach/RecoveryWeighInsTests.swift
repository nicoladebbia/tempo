//
// RecoveryWeighInsTests.swift
// Tempo
//

@testable import Tempo
import XCTest

final class RecoveryWeighInsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var end: Date { start.addingTimeInterval(80 * 60) }

    private func h(_ offsetMin: Double, _ kg: Double, _ src: String = "Withings") -> HealthWeightSample {
        HealthWeightSample(time: start.addingTimeInterval(offsetMin * 60), kg: kg, sourceName: src)
    }

    func testSourceMapping() {
        XCTAssertEqual(RecoveryWeighIns.source(forHealthSourceName: "Withings"), "withings")
        XCTAssertEqual(RecoveryWeighIns.source(forHealthSourceName: "Health Mate - Withings"), "withings")
        XCTAssertEqual(RecoveryWeighIns.source(forHealthSourceName: "withings app"), "withings")
        XCTAssertEqual(RecoveryWeighIns.source(forHealthSourceName: "Health"), "manual")
        XCTAssertEqual(RecoveryWeighIns.source(forHealthSourceName: ""), "manual")
    }

    func testWindowIsThreeHoursBeforeToTwoAndAHalfAfter() {
        let w = RecoveryWeighIns.window(start: start, end: end)
        XCTAssertEqual(start.timeIntervalSince(w.from), 3 * 3600)
        XCTAssertEqual(w.to.timeIntervalSince(end), 2.5 * 3600)
    }

    func testKeepsOnlyReadingsInsideTheWindow() {
        let samples = [h(-181, 78), h(-179, 78.1), h(0, 78), h(80 + 149, 76.8), h(80 + 151, 76.7)]
        let out = RecoveryWeighIns.select(health: samples, manual: [], start: start, end: end)
        XCTAssertEqual(out.map(\.kg), [78.1, 78, 76.8])
    }

    func testDropsImplausibleWeights() {
        let out = RecoveryWeighIns.select(health: [h(-10, 12), h(-5, 500), h(-2, 78)], manual: [], start: start, end: end)
        XCTAssertEqual(out.map(\.kg), [78])
    }

    func testMergesManualAndSortsAndManualWinsAtSameInstant() {
        let manual = [
            CoachWeighIn(time: start.addingTimeInterval(-10 * 60), kg: 77.9, source: "manual"),
            CoachWeighIn(time: start.addingTimeInterval(95 * 60), kg: 76.5, source: "manual"),
        ]
        let out = RecoveryWeighIns.select(health: [h(-10, 78.4), h(100, 76.6)], manual: manual, start: start, end: end)
        XCTAssertEqual(out.map(\.kg), [77.9, 76.5, 76.6])
        XCTAssertEqual(out.first?.source, "manual")
    }

    func testCapsTheListAtTwelveKeepingTheNewest() {
        let many = (0 ..< 20).map { h(Double($0), 70 + Double($0) / 10) }
        let out = RecoveryWeighIns.select(health: many, manual: [], start: start, end: end)
        XCTAssertEqual(out.count, RecoveryWeighIns.maxCount)
        XCTAssertEqual(out.last?.kg, 71.9)
    }

    func testEmptyInputGivesEmptyOutput() {
        XCTAssertTrue(RecoveryWeighIns.select(health: [], manual: [], start: start, end: end).isEmpty)
    }

    func testWithingsSourceIsKeptOnTheWeighIn() {
        let out = RecoveryWeighIns.select(health: [h(-5, 78, "Withings"), h(95, 76.8, "Health")], manual: [], start: start, end: end)
        XCTAssertEqual(out.map(\.source), ["withings", "manual"])
    }

    func testWaterWindowFollowsTheServersChosenWeighIns() {
        let ws = [
            CoachWeighIn(time: start.addingTimeInterval(-120 * 60), kg: 78.3, source: "manual"),
            CoachWeighIn(time: start.addingTimeInterval(-20 * 60), kg: 78.0, source: "withings"), // latest "before"
            CoachWeighIn(time: end.addingTimeInterval(20 * 60), kg: 76.8, source: "withings"), // earliest "after"
            CoachWeighIn(time: end.addingTimeInterval(140 * 60), kg: 76.5, source: "withings"), // later, ignored
        ]
        let w = RecoveryWeighIns.waterWindow(weighIns: ws, start: start, end: end, now: end.addingTimeInterval(5 * 3600))
        XCTAssertEqual(w.from, start.addingTimeInterval(-20 * 60))
        XCTAssertEqual(w.to, end.addingTimeInterval(20 * 60))
    }

    func testWaterWindowFallsBackWithoutWeighIns() {
        let now = end.addingTimeInterval(1800)
        let w = RecoveryWeighIns.waterWindow(weighIns: [], start: start, end: end, now: now)
        XCTAssertEqual(w.from, start.addingTimeInterval(-15 * 60))
        XCTAssertEqual(w.to, now)
    }

    func testMockServiceFiltersByRange() async throws {
        let mock = MockHealthKitService()
        mock.bodyMassSamples = [h(-300, 70), h(-10, 78), h(10, 77)]
        let w = RecoveryWeighIns.window(start: start, end: end)
        let got = try await mock.fetchBodyMassSamples(from: w.from, to: w.to)
        XCTAssertEqual(got.map(\.kg), [78, 77])
    }
}
