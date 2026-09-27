//
// PainReportTests.swift
// Tempo
//
// "This hurts" flow — severity-tier thresholds (mild <=3, moderate 4-6,
// severe 7+) and the 7-day caution window.
//

@testable import Tempo
import XCTest

final class PainReportTests: XCTestCase {
    private let cal = TrainingCalendar.iso8601

    private func date(_ string: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)!
    }

    // MARK: - Severity tiers

    func testSeverityTierBoundaries() {
        XCTAssertEqual(PainSeverityTier(severity: 1), .mild)
        XCTAssertEqual(PainSeverityTier(severity: 3), .mild)
        XCTAssertEqual(PainSeverityTier(severity: 4), .moderate)
        XCTAssertEqual(PainSeverityTier(severity: 6), .moderate)
        XCTAssertEqual(PainSeverityTier(severity: 7), .severe)
        XCTAssertEqual(PainSeverityTier(severity: 10), .severe)
    }

    func testSeverityClampedOnInit() {
        let report = PainReport(bodyArea: .knee, severity: 99)
        XCTAssertEqual(report.severity, 10)
        let low = PainReport(bodyArea: .knee, severity: 0)
        XCTAssertEqual(low.severity, 1)
    }

    // MARK: - Caution window

    func testRecentReport_withinWindow() {
        let exerciseID = UUID()
        let report = PainReport(date: date("2026-09-20"), bodyArea: .knee, severity: 5, exerciseID: exerciseID)
        let found = PainCaution.recentReport(for: exerciseID, in: [report], asOf: date("2026-09-25"), calendar: cal)
        XCTAssertNotNil(found, "5 days old — still inside the 7-day window")
    }

    func testRecentReport_outsideWindow() {
        let exerciseID = UUID()
        let report = PainReport(date: date("2026-09-10"), bodyArea: .knee, severity: 5, exerciseID: exerciseID)
        let found = PainCaution.recentReport(for: exerciseID, in: [report], asOf: date("2026-09-25"), calendar: cal)
        XCTAssertNil(found, "15 days old — outside the 7-day window")
    }

    func testRecentReport_pickMostRecentForSameExercise() {
        let exerciseID = UUID()
        let older = PainReport(date: date("2026-09-20"), bodyArea: .knee, severity: 5, exerciseID: exerciseID)
        let newer = PainReport(date: date("2026-09-23"), bodyArea: .shoulder, severity: 8, exerciseID: exerciseID)
        let found = PainCaution.recentReport(for: exerciseID, in: [older, newer], asOf: date("2026-09-25"), calendar: cal)
        XCTAssertEqual(found?.bodyArea, .shoulder)
    }

    func testRecentReport_ignoresOtherExercises() {
        let exerciseID = UUID()
        let report = PainReport(date: date("2026-09-24"), bodyArea: .knee, severity: 5, exerciseID: UUID())
        XCTAssertNil(PainCaution.recentReport(for: exerciseID, in: [report], asOf: date("2026-09-25"), calendar: cal))
    }
}
