//
// RecoveryCoachMathTests.swift
// Tempo
//

@testable import Tempo
import XCTest

final class RecoveryCoachMathTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String, endedHoursAgo: Double) -> CoachSession {
        let end = now.addingTimeInterval(-endedHoursAgo * 3600)
        return CoachSession(
            id: id, start: end.addingTimeInterval(-80 * 60), end: end, sportName: "soccer",
            strain: 14, kilojoules: 3500, averageHeartRate: 150, percentRecorded: 100
        )
    }

    func testFluidsUnknownIsNil() {
        XCTAssertNil(CoachFluidBreakdown(loggedMl: 0, quickAnswerLiters: nil, editedLiters: nil).liters)
    }

    func testFluidsNothingAnswerIsKnownZero() {
        XCTAssertEqual(CoachFluidBreakdown(loggedMl: 0, quickAnswerLiters: 0, editedLiters: nil).liters, 0)
    }

    func testFluidsSumLogsAndAnswer() throws {
        let l = try XCTUnwrap(CoachFluidBreakdown(loggedMl: 250, quickAnswerLiters: 0.75, editedLiters: nil).liters)
        XCTAssertEqual(l, 1.0, accuracy: 0.0001)
    }

    func testFluidsLogsAloneCount() throws {
        XCTAssertEqual(try XCTUnwrap(CoachFluidBreakdown(loggedMl: 500, quickAnswerLiters: nil, editedLiters: nil).liters), 0.5, accuracy: 0.0001)
    }

    func testFluidsEditReplacesEverything() {
        XCTAssertEqual(CoachFluidBreakdown(loggedMl: 500, quickAnswerLiters: 1.5, editedLiters: 0.3).liters, 0.3)
    }

    func testQuickAnswerBottlesAndLiters() {
        XCTAssertEqual(CoachQuickAnswerAction.allCases.map(\.bottles), [0, 0.5, 1, 2])
        XCTAssertEqual(CoachQuickAnswer(bottles: 0.5, bottleMl: 750, answeredAt: now).liters, 0.375, accuracy: 0.0001)
        XCTAssertEqual(CoachQuickAnswer(bottles: 2, bottleMl: 500, answeredAt: now).liters, 1.0, accuracy: 0.0001)
    }

    func testPickerPrefersLatestUnfinished() {
        let a = session("a", endedHoursAgo: 3), b = session("b", endedHoursAgo: 20)
        let pick = RecoverySessionPicker.focus(sessions: [b, a], now: now) { $0 == "a" }
        XCTAssertEqual(pick?.id, "b")
    }

    func testPickerFallsBackToLatestWhenAllReady() {
        let a = session("a", endedHoursAgo: 3), b = session("b", endedHoursAgo: 20)
        XCTAssertEqual(RecoverySessionPicker.focus(sessions: [b, a], now: now) { _ in true }?.id, "a")
    }

    func testPickerIgnoresOlderThan48HoursAndUnfinished() {
        let old = session("old", endedHoursAgo: 49)
        let running = CoachSession(
            id: "run", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600), sportName: nil,
            strain: nil, kilojoules: nil, averageHeartRate: nil, percentRecorded: nil
        )
        XCTAssertNil(RecoverySessionPicker.focus(sessions: [old, running], now: now) { _ in false })
    }

    func testFormatting() {
        XCTAssertEqual(RecoveryCoachFormat.litersRange(low: 1.503, high: 1.617), "1.5 to 1.6 L")
        XCTAssertEqual(RecoveryCoachFormat.litersRange(low: 1.51, high: 1.54), "1.5 L")
        XCTAssertEqual(RecoveryCoachFormat.sodiumRange(low: 345.56, high: 2602.55), "350 to 2600 mg")
        XCTAssertEqual(RecoveryCoachFormat.margin(10.71), "+/- 11%")
        XCTAssertEqual(RecoveryCoachFormat.coarse(25.7743), 25.8)
        XCTAssertEqual(RecoveryCoachFormat.coarse(-80.1912), -80.2)
        XCTAssertEqual(RecoveryCoachFormat.clock(75), "1:15")
        XCTAssertEqual(RecoveryCoachFormat.fluid(0.375), "375 mL")
        XCTAssertEqual(RecoveryCoachFormat.fluid(1.5), "1.5 L")
        XCTAssertEqual(RecoveryCoachFormat.fluid(1.25), "1.25 L")
        XCTAssertEqual(RecoveryCoachFormat.fluid(2), "2 L")
        XCTAssertEqual(RecoveryCoachFormat.fluid(0), "0 mL")
    }

    func testStoreQuickAnswerUsesBottleSizeAndPrunes() {
        let defaults = UserDefaults(suiteName: "coach-test-\(UUID().uuidString)")!
        let store = RecoveryCoachStore(defaults: defaults, key: "k")
        store.update { $0.bottleMl = 500 }
        store.recordQuickAnswer(sessionID: "s1", bottles: 2, now: now)
        XCTAssertEqual(store.read().quickAnswers["s1"]?.liters, 1.0)
        // 15 days later the answer is gone.
        store.update(now: now.addingTimeInterval(15 * 24 * 3600)) { _ in }
        XCTAssertNil(store.read().quickAnswers["s1"])
    }

    func testStoreManualWeighInsReplaceSameSecond() {
        let defaults = UserDefaults(suiteName: "coach-test-\(UUID().uuidString)")!
        let store = RecoveryCoachStore(defaults: defaults, key: "k")
        store.addManualWeighIn(CoachWeighIn(time: now, kg: 78, source: "manual"), now: now)
        store.addManualWeighIn(CoachWeighIn(time: now, kg: 77.5, source: "manual"), now: now)
        XCTAssertEqual(store.read().manualWeighIns.map(\.kg), [77.5])
        store.removeManualWeighIn(at: now)
        XCTAssertTrue(store.read().manualWeighIns.isEmpty)
    }

    func testStateRoundTripsACachedResult() throws {
        let json = """
        {"status":"needs_weigh_in","missing":["pre_weigh_in"],"notes":["n"]}
        """
        let r = try JSONDecoder().decode(CoachRecoveryResponse.self, from: Data(json.utf8))
        let defaults = UserDefaults(suiteName: "coach-test-\(UUID().uuidString)")!
        let store = RecoveryCoachStore(defaults: defaults, key: "k")
        store.update(now: now) { $0.results["s"] = CoachCachedResult(response: r, storedAt: now) }
        XCTAssertEqual(store.read().results["s"]?.response, r)
    }
}
