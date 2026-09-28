//
// SundayWrapUpReportTrackerTests.swift
// Tempo
//
// Sunday wrap-up feature — pins that "report sent this week" is keyed by
// BOTH the program and the served week, so a different program (or the same
// program's next served week) never reads as already-sent.
//

import Foundation
@testable import Tempo
import XCTest

final class SundayWrapUpReportTrackerTests: XCTestCase {
    /// An isolated suite per test so runs never see another test's (or a
    /// prior run's) leftover flag.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SundayWrapUpReportTrackerTests-\(UUID().uuidString)")!
    }

    private static func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = TrainingCalendar.iso8601
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }

    func testNotSentByDefault() {
        let defaults = makeDefaults()
        XCTAssertFalse(SundayWrapUpReportTracker.wasSent(programID: UUID(), weekMonday: Self.date("2026-09-21"), defaults: defaults))
    }

    func testMarkSentThenWasSentRoundTrips() {
        let defaults = makeDefaults()
        let programID = UUID()
        let weekMonday = Self.date("2026-09-21")

        SundayWrapUpReportTracker.markSent(programID: programID, weekMonday: weekMonday, defaults: defaults)

        XCTAssertTrue(SundayWrapUpReportTracker.wasSent(programID: programID, weekMonday: weekMonday, defaults: defaults))
    }

    func testDifferentWeekForSameProgramIsNotMarkedSent() {
        let defaults = makeDefaults()
        let programID = UUID()
        SundayWrapUpReportTracker.markSent(programID: programID, weekMonday: Self.date("2026-09-21"), defaults: defaults)

        XCTAssertFalse(SundayWrapUpReportTracker.wasSent(programID: programID, weekMonday: Self.date("2026-09-28"), defaults: defaults))
    }

    func testDifferentProgramSameWeekIsNotMarkedSent() {
        let defaults = makeDefaults()
        let weekMonday = Self.date("2026-09-21")
        SundayWrapUpReportTracker.markSent(programID: UUID(), weekMonday: weekMonday, defaults: defaults)

        XCTAssertFalse(SundayWrapUpReportTracker.wasSent(programID: UUID(), weekMonday: weekMonday, defaults: defaults))
    }
}
