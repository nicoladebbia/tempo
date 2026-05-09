//
// AccountabilityEngineTests.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

@testable import Tempo
import XCTest

// MARK: - Accountability Engine Tests

// Per BUILD_PLAN Step 19.3 — Unit tests for accountability state evaluation, leisure unlock, milestones.

final class AccountabilityEngineTests: XCTestCase {
    private var engine: AccountabilityEngine!

    override func setUp() {
        super.setUp()
        engine = AccountabilityEngine()
    }

    // MARK: - State Evaluation

    @MainActor
    func testMorningSetupWhenNoNonNegotiables() {
        let accountability = DailyAccountability(date: Date())
        let ps5 = engine.ps5Time()
        let state = engine.evaluateState(accountability: accountability, override: nil, ps5Time: ps5)
        XCTAssertEqual(state, .morningSetup)
    }

    @MainActor
    func testOverrideTakesPrecedence() {
        let accountability = DailyAccountability(date: Date())
        let ps5 = engine.ps5Time()
        let state = engine.evaluateState(accountability: accountability, override: .sickDay, ps5Time: ps5)
        XCTAssertEqual(state, .overrideActive)
    }

    @MainActor
    func testUnlockedWhenLeisureUnlocked() {
        let accountability = DailyAccountability(date: Date(), leisureUnlocked: true)
        let ps5 = engine.ps5Time()
        let state = engine.evaluateState(accountability: accountability, override: nil, ps5Time: ps5)
        XCTAssertEqual(state, .unlocked)
    }

    @MainActor
    func testDayFailedWhenPastPS5Time() throws {
        let accountability = DailyAccountability(date: Date())
        // PS5 time in the past
        let pastPS5 = try XCTUnwrap(Calendar.current.date(byAdding: .hour, value: -1, to: Date()))
        let state = engine.evaluateState(accountability: accountability, override: nil, ps5Time: pastPS5)
        XCTAssertEqual(state, .dayFailed)
    }

    // MARK: - Leisure Unlock

    @MainActor
    func testCheckLeisureUnlockFalseWhenIncomplete() {
        let accountability = DailyAccountability(date: Date())
        XCTAssertFalse(engine.checkLeisureUnlock(accountability: accountability))
    }

    // MARK: - Daily Score

    @MainActor
    func testDailyScoreZeroWhenNoNonNegotiables() {
        let accountability = DailyAccountability(date: Date())
        let score = engine.calculateDailyScore(accountability: accountability)
        XCTAssertEqual(score, 0)
    }

    // MARK: - Streak Milestones

    func testStreakMilestone3Day() {
        XCTAssertEqual(engine.streakMilestone(count: 3), .threeDay)
    }

    func testStreakMilestone7Day() {
        XCTAssertEqual(engine.streakMilestone(count: 7), .oneWeek)
    }

    func testStreakMilestone30Day() {
        XCTAssertEqual(engine.streakMilestone(count: 30), .oneMonth)
    }

    func testStreakMilestone100Day() {
        XCTAssertEqual(engine.streakMilestone(count: 100), .century)
    }

    func testStreakMilestoneNone() {
        XCTAssertNil(engine.streakMilestone(count: 4))
        XCTAssertNil(engine.streakMilestone(count: 10))
        XCTAssertNil(engine.streakMilestone(count: 99))
    }

    // MARK: - Weekend Detection

    func testIsWeekendForSunday() throws {
        // Create a known Sunday (2026-03-29 is a Sunday)
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 29
        let sunday = try XCTUnwrap(Calendar.current.date(from: comps))
        XCTAssertTrue(engine.isWeekend(date: sunday))
    }

    func testIsWeekdayForMonday() throws {
        // 2026-03-30 is a Monday
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 30
        let monday = try XCTUnwrap(Calendar.current.date(from: comps))
        XCTAssertFalse(engine.isWeekend(date: monday))
    }

    // MARK: - PS5 Time

    func testPS5TimeWeekday() throws {
        // Monday 2026-03-30
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 30
        let monday = try XCTUnwrap(Calendar.current.date(from: comps))
        let ps5 = engine.ps5Time(for: monday)
        let hour = Calendar.current.component(.hour, from: ps5)
        let minute = Calendar.current.component(.minute, from: ps5)
        XCTAssertEqual(hour, 19)
        XCTAssertEqual(minute, 30)
    }

    func testPS5TimeWeekend() throws {
        // Sunday 2026-03-29
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 29
        let sunday = try XCTUnwrap(Calendar.current.date(from: comps))
        let ps5 = engine.ps5Time(for: sunday)
        let hour = Calendar.current.component(.hour, from: ps5)
        let minute = Calendar.current.component(.minute, from: ps5)
        XCTAssertEqual(hour, 21)
        XCTAssertEqual(minute, 0)
    }

    // MARK: - Streak Milestone Properties

    func testStreakMilestoneXPBonus() {
        XCTAssertEqual(StreakMilestone.threeDay.xpBonus, 0)
        XCTAssertEqual(StreakMilestone.oneWeek.xpBonus, 100)
        XCTAssertEqual(StreakMilestone.oneMonth.xpBonus, 300)
        XCTAssertEqual(StreakMilestone.century.xpBonus, 1000)
    }

    func testStreakMilestoneBonusHour() {
        XCTAssertTrue(StreakMilestone.fiveDay.grantsBonusHour)
        XCTAssertFalse(StreakMilestone.threeDay.grantsBonusHour)
        XCTAssertFalse(StreakMilestone.oneWeek.grantsBonusHour)
    }
}
