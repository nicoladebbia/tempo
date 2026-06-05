//
// AccountabilityEngineTests.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - Accountability Engine Tests

// Per BUILD_PLAN Step 19.3 — Unit tests for accountability state evaluation, leisure unlock, milestones.

final class AccountabilityEngineTests: XCTestCase {
    // MARK: Internal

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
        // dayFailed requires ACTUAL incomplete work — a day with no tasks set
        // up is morningSetup, not failed (you can't fail what you never
        // started). Add one incomplete non-negotiable so this is a real
        // "past PS5 with work undone" scenario.
        accountability.nonNegotiableProgress = [
            NonNegotiableProgress(date: Date(), targetValue: 1, isCompleted: false),
        ]
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

    // MARK: - Non-Negotiable Loading (regression: defaults sheet → empty Lockdown)

    /// Regression test: when a DailyAccountability already exists for today (e.g.
    /// auto-created on first Lockdown open) but has no progress entries, the
    /// next call to loadTodayNonNegotiables must populate progress for the
    /// non-negotiables that were added afterward through the setup sheet.
    @MainActor
    func testLoadTodayPopulatesProgressForExistingAccountability() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        // 1. First load — no NNs exist yet, so accountability is created empty.
        let first = engine.loadTodayNonNegotiables(modelContext: context)
        XCTAssertEqual(first.totalCount, 0, "Empty accountability expected when no NNs are configured")

        // 2. User opens setup sheet and adds defaults.
        struct Template {
            let name: String
            let type: NonNegotiableType
            let target: Double
            let tracking: TrackingMethod
        }
        let templates: [Template] = [
            Template(name: "Study", type: .study, target: 120, tracking: .timer),
            Template(name: "Training", type: .train, target: 1, tracking: .autoWhoop),
            Template(name: "Meals", type: .meals, target: 3, tracking: .manual),
            Template(name: "Sleep", type: .sleep, target: 7, tracking: .autoHealthkit),
        ]
        for (i, t) in templates.enumerated() {
            context.insert(NonNegotiable(
                name: t.name,
                type: t.type,
                targetValue: t.target,
                trackingMethod: t.tracking,
                order: i
            ))
        }
        try context.save()

        // 3. Lockdown reloads on sheet dismiss — must hydrate progress entries.
        let second = engine.loadTodayNonNegotiables(modelContext: context)
        XCTAssertEqual(second.totalCount, 4, "Defaults must populate after sheet dismissal")
        XCTAssertEqual(second.id, first.id, "Should reuse the same DailyAccountability row")

        let types = Set((second.nonNegotiableProgress ?? []).compactMap { $0.nonNegotiable?.type })
        XCTAssertEqual(types, [.study, .train, .meals, .sleep])

        // 4. Repeated load is idempotent — no duplicate progress entries.
        let third = engine.loadTodayNonNegotiables(modelContext: context)
        XCTAssertEqual(third.totalCount, 4, "Repeated loads must not duplicate progress")
    }

    /// Adding a new non-negotiable mid-day must inject a progress row for it
    /// without disturbing rows that already exist (and may have progress on them).
    @MainActor
    func testLoadTodayAddsProgressForNewlyAddedNonNegotiable() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)

        context.insert(NonNegotiable(
            name: "Study", type: .study, targetValue: 120,
            trackingMethod: .timer, order: 0
        ))
        try context.save()

        let acc = engine.loadTodayNonNegotiables(modelContext: context)
        XCTAssertEqual(acc.totalCount, 1)

        // User adds a second NN later in the day.
        context.insert(NonNegotiable(
            name: "Sleep", type: .sleep, targetValue: 7,
            trackingMethod: .autoHealthkit, order: 1
        ))
        try context.save()

        let updated = engine.loadTodayNonNegotiables(modelContext: context)
        XCTAssertEqual(updated.totalCount, 2)
    }

    // MARK: Private

    private var engine: AccountabilityEngine!
}
