//
// WeeklyUploadPromptCardTitleTests.swift
// Tempo
//
// The wrap-up card names the week it covers, never "<program name>'s week".
//

@testable import Tempo
import XCTest

@MainActor
final class WeeklyUploadPromptCardTitleTests: XCTestCase {
    private func date(_ string: String, hour: Int = 10) -> Date {
        let f = DateFormatter()
        f.calendar = TrainingCalendar.iso8601
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)!.addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func program() -> TrainerProgram {
        TrainerProgram(name: "Coach — Week 3", startDate: date("2026-09-21"), weeks: [ProgramWeek(days: [])], sourceKind: "text")
    }

    func testWeekdayTitleNamesLastWeekAndItsDates() {
        let title = WeeklyUploadPromptCard.title(for: program(), now: date("2026-10-01"))
        XCTAssertTrue(title.hasPrefix("Wrap up last week · 21–27"), title)
        XCTAssertFalse(title.contains("Coach"))
    }

    func testSundayTitleNamesThisWeek() {
        let title = WeeklyUploadPromptCard.title(for: program(), now: date("2026-09-27", hour: 20))
        XCTAssertTrue(title.hasPrefix("Wrap up this week · 21–27"), title)
    }

    func testRangeAcrossMonthsShowsBothMonths() {
        let title = WeeklyUploadPromptCard.title(for: program(), now: date("2026-10-07"))
        XCTAssertTrue(title.contains(" – "), title)
        XCTAssertTrue(title.hasPrefix("Wrap up last week · 28"), title)
    }
}
