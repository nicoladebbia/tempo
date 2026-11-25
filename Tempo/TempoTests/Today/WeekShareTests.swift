//
// WeekShareTests.swift
// TempoTests
//
// The week card from the week in review says what the review page says (sessions,
// study) and what the Arena keeps (XP for the same Monday-to-Sunday week).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WeekShareTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let calendar = ArenaCalendar.calendar()
    /// A Monday.
    private let monday = ArenaCalendar.weekStart(containing: Date(timeIntervalSince1970: 1_800_000_000))

    override func setUp() async throws {
        container = try TempoModelContainer.create(inMemory: true)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: monday)!
    }

    private func addXP(_ amount: Int, on date: Date) {
        context.insert(XPEvent(date: date, source: .workout, amount: amount, description: "test"))
    }

    func testXPCountsOnlyTheSevenDaysOfThatWeek() throws {
        addXP(100, on: day(-1)) // the Sunday before
        addXP(50, on: day(0))
        addXP(70, on: day(6))
        addXP(900, on: day(7)) // the Monday after
        try context.save()
        XCTAssertEqual(WeekShare.xp(in: context, weekStart: monday), 120)
    }

    func testAWeekWithNoXPRowsIsZero() {
        XCTAssertEqual(WeekShare.xp(in: context, weekStart: monday), 0)
    }

    func testTheCardCarriesTheReviewNumbers() {
        var totals = WeekTotals()
        totals.sessions = 3
        totals.studyMinutes = 135
        let review = WeekReview(weekStart: monday, thisWeek: totals, lastWeek: WeekTotals())
        let card = WeekShare.card(for: review, xp: 420)
        XCTAssertEqual(card.hero, "420")
        XCTAssertEqual(card.heroUnit, "XP")
        XCTAssertEqual(card.stats.first { $0.label == "Workouts" }?.value, "3")
        XCTAssertEqual(card.stats.first { $0.label == "Study" }?.value, "2h 15m")
        XCTAssertNil(card.stats.first { $0.label == "Rank" }, "Today does not know the friends board")
    }

    func testOneSessionReadsAsAWorkoutNotWorkouts() {
        var totals = WeekTotals()
        totals.sessions = 1
        let review = WeekReview(weekStart: monday, thisWeek: totals, lastWeek: WeekTotals())
        XCTAssertNotNil(WeekShare.card(for: review, xp: 0).stats.first { $0.label == "Workout" })
    }
}
