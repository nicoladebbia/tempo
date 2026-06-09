//
// MatchPeriodizationTests.swift
// Tempo
//
// Proves a DATED match re-shapes the deterministic week (docs/INTELLIGENT_TRAINING_SYSTEM.md
// §9 D3, §14): the match day becomes T-0 (football), and the day before becomes
// T-1 (no heavy legs → swapped to upper), even when the match falls off a usual
// football weekday. This is the free deterministic re-periodization that match
// entry triggers — no AI call.
//

@testable import Tempo
import XCTest

final class MatchPeriodizationTests: XCTestCase {
    private var engine: TrainingEngine!
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    override func setUp() {
        super.setUp()
        engine = TrainingEngine()
    }

    /// A Monday start so day offsets map to known weekdays.
    private func monday() -> Date {
        // 2023-11-13 is a Monday.
        let base = Date(timeIntervalSince1970: 1_699_858_800) // 2023-11-13 ~00:00 ET
        return cal.startOfDay(for: base)
    }

    private func plan(_ plans: [WorkoutPlan], dayOffset: Int) -> WorkoutPlan? {
        let target = cal.date(byAdding: .day, value: dayOffset, to: monday())!
        return plans.first { cal.isDate($0.date, inSameDayAs: target) }
    }

    /// With no matches and no football days, a mid-week day is a normal gym
    /// session, not football — the baseline the match test contrasts against.
    func testNoMatchNoFootballIsNotMatchDay() {
        let plans = engine.generateWeekPlan(
            startDate: monday(),
            recoveryScores: [:],
            footballDays: ActiveDays(rawValue: 0),
            split: .pushPullLegs
        )
        // Wednesday (offset 2) should not be a football/match day.
        XCTAssertNotEqual(plan(plans, dayOffset: 2)?.type, .football)
    }

    func testDatedMatchMakesThatDayFootball() {
        // Match on Wednesday (offset 2) — a day that is NOT a football weekday.
        let matchDay = cal.startOfDay(for: cal.date(byAdding: .day, value: 2, to: monday())!)
        let plans = engine.generateWeekPlan(
            startDate: monday(),
            recoveryScores: [:],
            footballDays: ActiveDays(rawValue: 0),
            split: .pushPullLegs,
            matchDayKeys: [matchDay]
        )
        XCTAssertEqual(plan(plans, dayOffset: 2)?.type, .football, "match day must become T-0 football")
    }

    func testDatedMatchProtectsTheDayBefore() {
        // Match Wednesday (offset 2) → Tuesday (offset 1) is T-1: no heavy legs.
        let matchDay = cal.startOfDay(for: cal.date(byAdding: .day, value: 2, to: monday())!)
        let plans = engine.generateWeekPlan(
            startDate: monday(),
            recoveryScores: [:],
            footballDays: ActiveDays(rawValue: 0),
            split: .pushPullLegs,
            matchDayKeys: [matchDay]
        )
        // The T-1 day must not be a legs day (the leg-swap rule). PPL puts legs
        // on the 3rd training slot; the exact type depends on assignment, but
        // the invariant is simply: T-1 is never .legs.
        XCTAssertNotEqual(plan(plans, dayOffset: 1)?.type, .legs, "T-1 must swap legs away")
    }
}
