//
// SupplementReorderServiceTests.swift
// Tempo
//
// `SupplementReorderService` is pure (no SwiftData fetch/save) — tests build
// `Supplement` + `[SupplementIntakeLog]` by hand. Coverage: tracked/untracked
// detection, days-left estimation (logged rate + the daily fallback),
// low-stock + once-per-restock-cycle alert gating, and the taken/undo/restock
// mutations.
//

@testable import Tempo
import XCTest

@MainActor
final class SupplementReorderServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!

    private func log(_ name: String, daysAgo: Int) -> SupplementIntakeLog {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return SupplementIntakeLog(supplementName: name, day: day)
    }

    // MARK: - isTracked

    func testIsTracked_falseWithNoQuantityInfoAtAll() {
        let supp = Supplement(name: "Creatine", kind: .creatine)
        XCTAssertFalse(SupplementReorderService.isTracked(supp))
    }

    func testIsTracked_trueWithServingsRemainingOrContainerSize() {
        let withRemaining = Supplement(name: "A", kind: .other, servingsRemaining: 10)
        XCTAssertTrue(SupplementReorderService.isTracked(withRemaining))

        let withContainerOnly = Supplement(name: "B", kind: .other)
        withContainerOnly.servingsPerContainer = 60
        XCTAssertTrue(SupplementReorderService.isTracked(withContainerOnly))
    }

    // MARK: - daysLeft

    func testDaysLeft_nilWhenUntracked() {
        let supp = Supplement(name: "Creatine", kind: .creatine)
        XCTAssertNil(SupplementReorderService.daysLeft(for: supp, recentLogs: [], asOf: now, calendar: calendar))
    }

    func testDaysLeft_zeroWhenTrackedButEmpty() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 0)
        supp.servingsPerContainer = 90
        XCTAssertEqual(SupplementReorderService.daysLeft(for: supp, recentLogs: [], asOf: now, calendar: calendar), 0)
    }

    func testDaysLeft_dailyFallbackWhenNoLoggedHistoryYet() {
        // Brand-new daily supplement, no intake logs at all → assume 1/day.
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 30, takeDaily: true)
        XCTAssertEqual(SupplementReorderService.daysLeft(for: supp, recentLogs: [], asOf: now, calendar: calendar), 30)
    }

    func testDaysLeft_nilForConditionalItemWithNoLoggedIntake() {
        // Non-daily, tracked, but never logged in the window — no reliable rate.
        let supp = Supplement(name: "Whey", kind: .protein, servingsRemaining: 20)
        XCTAssertNil(SupplementReorderService.daysLeft(for: supp, recentLogs: [], asOf: now, calendar: calendar))
    }

    func testDaysLeft_estimatesFromLoggedRateOverTheWindow() {
        // Taken on 7 of the observed days → the window is inclusive of both
        // endpoints (today AND `intakeWindowDays` ago), so 15 observed days.
        let supp = Supplement(name: "Whey", kind: .protein, servingsRemaining: 20)
        let logs = (0 ..< 14).filter { $0 % 2 == 0 }.map { log("Whey", daysAgo: $0) }
        let days = SupplementReorderService.daysLeft(for: supp, recentLogs: logs, asOf: now, calendar: calendar)
        // 7 matching days / 15 observed days ≈ 0.4667/day → floor(20 / 0.4667) = 42.
        XCTAssertEqual(days, 42)
    }

    func testDaysLeft_ignoresLogsForOtherSupplementsAndOutsideWindow() {
        let supp = Supplement(name: "Whey", kind: .protein, servingsRemaining: 14, takeDaily: true)
        var logs = (0 ..< 14).map { log("Whey", daysAgo: $0) } // every day in-window
        logs.append(log("Creatine", daysAgo: 1)) // different supplement, ignored
        logs.append(log("Whey", daysAgo: 30)) // outside the 14-day window, ignored
        let days = SupplementReorderService.daysLeft(for: supp, recentLogs: logs, asOf: now, calendar: calendar)
        // 14 matching days / 15 observed days → 14 / (14/15) = 15.
        XCTAssertEqual(days, 15)
    }

    // MARK: - needsReorder / shouldSendReorderAlert

    func testNeedsReorder_trueAtOrBelowThreshold() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 7, takeDaily: true)
        XCTAssertTrue(SupplementReorderService.needsReorder(for: supp, recentLogs: [], asOf: now, calendar: calendar))
    }

    func testNeedsReorder_falseAboveThreshold() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 30, takeDaily: true)
        XCTAssertFalse(SupplementReorderService.needsReorder(for: supp, recentLogs: [], asOf: now, calendar: calendar))
    }

    func testNeedsReorder_falseWhenDaysLeftUnknown() {
        let supp = Supplement(name: "Whey", kind: .protein, servingsRemaining: 20) // conditional, no logs
        XCTAssertFalse(SupplementReorderService.needsReorder(for: supp, recentLogs: [], asOf: now, calendar: calendar))
    }

    func testShouldSendReorderAlert_trueOnFirstLowStockWithNoPriorAlert() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 5, takeDaily: true)
        XCTAssertTrue(SupplementReorderService.shouldSendReorderAlert(for: supp, recentLogs: [], asOf: now, calendar: calendar))
    }

    func testShouldSendReorderAlert_falseWhenAlreadyAlertedThisCycle() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 5, takeDaily: true)
        supp.lastReorderAlertAt = calendar.date(byAdding: .day, value: -1, to: now)
        XCTAssertFalse(SupplementReorderService.shouldSendReorderAlert(for: supp, recentLogs: [], asOf: now, calendar: calendar))
    }

    func testShouldSendReorderAlert_trueAgainAfterARestockStartsANewCycle() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 5, takeDaily: true)
        supp.lastReorderAlertAt = calendar.date(byAdding: .day, value: -10, to: now)
        supp.lastRestockedAt = calendar.date(byAdding: .day, value: -5, to: now) // restocked AFTER the last alert
        XCTAssertTrue(SupplementReorderService.shouldSendReorderAlert(for: supp, recentLogs: [], asOf: now, calendar: calendar))
    }

    func testShouldSendReorderAlert_falseWhenNotLowStock() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 60, takeDaily: true)
        XCTAssertFalse(SupplementReorderService.shouldSendReorderAlert(for: supp, recentLogs: [], asOf: now, calendar: calendar))
    }

    // MARK: - Mutations

    func testApplyTaken_decrementsWhenTracked() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 10)
        SupplementReorderService.applyTaken(to: supp)
        XCTAssertEqual(supp.servingsRemaining, 9)
    }

    func testApplyTaken_clampsAtZero() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 0)
        supp.servingsPerContainer = 30 // tracked via container size even though remaining is 0
        SupplementReorderService.applyTaken(to: supp)
        XCTAssertEqual(supp.servingsRemaining, 0)
    }

    func testApplyTaken_noOpWhenUntracked() {
        let supp = Supplement(name: "Creatine", kind: .creatine) // never tracked
        SupplementReorderService.applyTaken(to: supp)
        XCTAssertEqual(supp.servingsRemaining, 0)
    }

    func testApplyUndo_addsOneBackWhenTracked() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 9)
        SupplementReorderService.applyUndo(to: supp)
        XCTAssertEqual(supp.servingsRemaining, 10)
    }

    func testApplyUndo_cappedAtFullContainer() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 30)
        supp.servingsPerContainer = 30
        SupplementReorderService.applyUndo(to: supp)
        XCTAssertEqual(supp.servingsRemaining, 30, "Undo must not overshoot a full container")
    }

    func testApplyUndo_noOpWhenUntracked() {
        let supp = Supplement(name: "Creatine", kind: .creatine)
        SupplementReorderService.applyUndo(to: supp)
        XCTAssertEqual(supp.servingsRemaining, 0)
    }

    func testRestock_resetsToFullContainerAndStartsNewCycle() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 2)
        supp.servingsPerContainer = 90
        SupplementReorderService.restock(supp, at: now)
        XCTAssertEqual(supp.servingsRemaining, 90)
        XCTAssertEqual(supp.lastRestockedAt, now)
    }

    func testRestock_leavesRemainingUnchangedWhenContainerSizeUnknown() {
        let supp = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: 2)
        SupplementReorderService.restock(supp, at: now)
        XCTAssertEqual(supp.servingsRemaining, 2, "No known container size — can't reset to a number we don't know")
        XCTAssertEqual(supp.lastRestockedAt, now)
    }
}
