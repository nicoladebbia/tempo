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

    private func startKey(_ offset: Int) -> Date {
        cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: monday())!)
    }

    func testDatedMatchMakesThatDayFootball() {
        // Match on Thursday (offset 3) — NOT a football weekday (none are set).
        let plans = engine.generateWeekPlan(
            startDate: monday(),
            recoveryScores: [:],
            footballDays: ActiveDays(rawValue: 0),
            split: .pushPullLegs,
            matchDayKeys: [startKey(3)]
        )
        XCTAssertEqual(plan(plans, dayOffset: 3)?.type, .football, "match day must become T-0 football")
    }

    /// The load-bearing test: prove the match SWAPS legs off T-1, by contrasting
    /// the SAME day with and without the match. PPL from a green Monday assigns
    /// push/pull/LEGS to Mon/Tue/Wed — so Wednesday (offset 2) is naturally a
    /// legs day. A match on Thursday (offset 3) makes Wednesday T-1 → must swap.
    func testDatedMatchSwapsLegsOffTMinus1() {
        // Baseline: no match → Wednesday is legs (proves the day is a real legs
        // day, so the swap below is not vacuous).
        let baseline = engine.generateWeekPlan(
            startDate: monday(),
            recoveryScores: [:],
            footballDays: ActiveDays(rawValue: 0),
            split: .pushPullLegs
        )
        XCTAssertEqual(plan(baseline, dayOffset: 2)?.type, .legs, "precondition: offset-2 is naturally a legs day")

        // With a Thursday match, Wednesday (T-1) must no longer be legs.
        let withMatch = engine.generateWeekPlan(
            startDate: monday(),
            recoveryScores: [:],
            footballDays: ActiveDays(rawValue: 0),
            split: .pushPullLegs,
            matchDayKeys: [startKey(3)]
        )
        XCTAssertNotEqual(plan(withMatch, dayOffset: 2)?.type, .legs, "T-1 must swap legs away when a match follows")
    }

    /// A FRIENDLY (non-competitive) match is still a T-0 session day, but must
    /// NOT taper the day before — honouring the isCompetitive toggle. Thursday
    /// match present in matchDayKeys (T-0) but absent from competitiveMatchDayKeys
    /// → Wednesday stays its natural legs day.
    func testFriendlyMatchDoesNotTaperTMinus1() {
        let plans = engine.generateWeekPlan(
            startDate: monday(),
            recoveryScores: [:],
            footballDays: ActiveDays(rawValue: 0),
            split: .pushPullLegs,
            matchDayKeys: [startKey(3)],          // friendly is still T-0…
            competitiveMatchDayKeys: []           // …but drives no T-1 taper
        )
        XCTAssertEqual(plan(plans, dayOffset: 3)?.type, .football, "friendly is still a T-0 session day")
        XCTAssertEqual(plan(plans, dayOffset: 2)?.type, .legs, "friendly must NOT swap legs off T-1")
    }
}
