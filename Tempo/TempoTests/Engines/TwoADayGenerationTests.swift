//
// TwoADayGenerationTests.swift
// Tempo
//
// Requirement (b): the week generator decides, on its own, which GYM days can
// also carry an easy cardio SECOND session ("gym + cardio two-a-days"). The
// decision is week-level (§21) — it lives on the persisted WorkoutPlan, not the
// transient daily prescription. These pin the eligibility gate: green recovery,
// upper-body lift only (never legs/lower — protect the legs), never the day
// before a match, capped per week, cardio modality = the learned (d) preference.
//

@testable import Tempo
import XCTest

final class TwoADayGenerationTests: XCTestCase {
    private let engine = TrainingEngine()
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// A fixed Monday (2023-11-13) as week start — matches the sibling engine
    /// tests so the day→type mapping is deterministic.
    private var monday: Date {
        let base = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 (Tue)
        return cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: base))!
    }

    /// A PPL week (push, pull, legs, push, pull, legs across Mon–Sat) with no
    /// football, all-green recovery. PPL gives a clean upper/legs mix so the
    /// legs-exclusion is directly observable.
    private func pplWeek(
        emphasis: BlockEmphasis = .physique,
        easyModalityPreference: [WorkoutType] = [.pool, .run],
        matchDayKeys: Set<Date> = []
    ) -> [WorkoutPlan] {
        engine.generateWeekPlan(
            startDate: monday,
            recoveryScores: [:], // no data → green default everywhere
            footballDays: ActiveDays(rawValue: 0),
            split: .pushPullLegs,
            matchDayKeys: matchDayKeys,
            emphasis: emphasis,
            easyModalityPreference: easyModalityPreference,
            // Reference = the week's Monday, so every day is "today or later" and
            // the past-day skip never fires — pins the eligibility, not the clock.
            referenceDate: monday
        )
    }

    private func twoADays(_ plans: [WorkoutPlan]) -> [WorkoutPlan] {
        plans.filter { $0.isTwoADay }
    }

    // MARK: - The gate

    func testUpperGymDaysEarnACardioSecondSession() {
        let plans = pplWeek()
        let seconds = twoADays(plans)
        XCTAssertFalse(seconds.isEmpty, "Green upper-body gym days should earn a cardio second session")
        // Every two-a-day must be an upper-body lift carrying a cardio second.
        for p in seconds {
            XCTAssertTrue([.push, .pull, .upper].contains(p.type),
                          "A two-a-day's PRIMARY must be an upper-body lift, got \(p.type)")
            XCTAssertTrue([.run, .pool].contains(p.secondarySessionType),
                          "The second session must be easy cardio, got \(String(describing: p.secondarySessionType))")
        }
    }

    func testLegDaysNeverGetASecondSession() {
        let plans = pplWeek()
        for p in plans where p.type == .legs || p.type == .lower {
            XCTAssertFalse(p.isTwoADay, "Legs/lower days must never stack cardio — protect the legs")
        }
    }

    func testRedRecoveryDayNeverTwoADays() {
        // Force Wednesday (offset 2 = the first legs day) AND Monday (push) red.
        let monKey = cal.startOfDay(for: monday)
        let plans = engine.generateWeekPlan(
            startDate: monday,
            recoveryScores: [monKey: 20], // Monday red
            footballDays: ActiveDays(rawValue: 0),
            split: .pushPullLegs,
            matchDayKeys: [],
            emphasis: .physique
        )
        // Monday is now mobility (red) — it can't be a two-a-day.
        let mondayPlan = plans.first { cal.isDate($0.date, inSameDayAs: monday) }
        XCTAssertNotNil(mondayPlan)
        XCTAssertFalse(mondayPlan?.isTwoADay ?? true, "A red-recovery day must never carry a second session")
    }

    func testDayBeforeMatchNeverTwoADays() {
        // Wednesday is a dated match → Tuesday is T-1. Tuesday's pull day must
        // NOT earn a cardio second (no added pre-game load).
        let wednesday = cal.date(byAdding: .day, value: 2, to: monday)!
        let plans = pplWeek(matchDayKeys: [cal.startOfDay(for: wednesday)])
        let tuesday = cal.date(byAdding: .day, value: 1, to: monday)!
        let tuePlan = plans.first { cal.isDate($0.date, inSameDayAs: tuesday) }
        XCTAssertNotNil(tuePlan)
        XCTAssertFalse(tuePlan?.isTwoADay ?? true, "T-1 (day before a match) must never two-a-day")
    }

    // MARK: - The cap

    func testPhysiqueCapIsTwoPerWeek() {
        XCTAssertLessThanOrEqual(twoADays(pplWeek(emphasis: .physique)).count, 2,
                                 "Physique earns at most two two-a-days per week")
    }

    func testSoccerCapIsOnePerWeek() {
        XCTAssertLessThanOrEqual(twoADays(pplWeek(emphasis: .soccer)).count, 1,
                                 "Soccer is already cardio-loaded by football — at most one two-a-day")
    }

    // MARK: - Modality follows the learned (d) preference

    func testSecondSessionFollowsLearnedPreferenceLeader() {
        let runFirst = twoADays(pplWeek(easyModalityPreference: [.run, .pool]))
        XCTAssertFalse(runFirst.isEmpty)
        for p in runFirst {
            XCTAssertEqual(p.secondarySessionType, .run,
                           "A run-leaning learner should give a running second session")
        }
        let poolFirst = twoADays(pplWeek(easyModalityPreference: [.pool, .run]))
        XCTAssertFalse(poolFirst.isEmpty)
        for p in poolFirst {
            XCTAssertEqual(p.secondarySessionType, .pool,
                           "A pool-leaning learner should give a pool second session")
        }
    }

    // MARK: - Custom split (the device case — this path used to bypass two-a-days)

    func testCustomSplitAlsoEarnsTwoADays() {
        // Mon..Sun map of upper lifts + legs + rest. Green everywhere, no football.
        let map: [WorkoutType] = [.push, .pull, .upper, .legs, .push, .rest, .rest]
        let plans = engine.generateWeekPlan(
            startDate: monday,
            recoveryScores: [:],
            footballDays: ActiveDays(rawValue: 0),
            split: .custom,
            customWeekdayMap: map,
            matchDayKeys: [],
            emphasis: .physique,
            // Anchor "today" to the week's Monday so no day counts as past.
            referenceDate: monday
        )
        let seconds = twoADays(plans)
        XCTAssertFalse(seconds.isEmpty,
                       "A CUSTOM split's green upper days must earn two-a-days too (this path used to skip it)")
        for p in seconds {
            XCTAssertTrue([.push, .pull, .upper].contains(p.type),
                          "Only upper-body custom days two-a-day, never legs/rest")
        }
    }

    // MARK: - (b) "Prefer future days" — the weekly slot never lands on a past day

    func testTwoADaySlotSkipsPastDaysToTheNextEligibleDay() {
        // Physique PPL, cap = 2. Anchor "today" to WEDNESDAY (offset 2). Mon/Tue
        // are now in the past; the two-a-day slots must skip them and land only
        // on today-or-future upper days (Thu push / Fri pull), never Mon/Tue.
        let wednesday = cal.date(byAdding: .day, value: 2, to: monday)!
        let plans = engine.generateWeekPlan(
            startDate: monday,
            recoveryScores: [:],
            footballDays: ActiveDays(rawValue: 0),
            split: .pushPullLegs,
            matchDayKeys: [],
            emphasis: .physique,
            referenceDate: wednesday
        )
        let seconds = twoADays(plans)
        XCTAssertFalse(seconds.isEmpty, "Future upper days should still earn two-a-days")
        for p in seconds {
            XCTAssertGreaterThanOrEqual(
                cal.startOfDay(for: p.date), cal.startOfDay(for: wednesday),
                "A two-a-day must never be assigned to a day already in the past (\(p.date))"
            )
        }
    }

    // MARK: - Model invariants

    func testSingleSessionDayIsNotTwoADay() {
        let plan = WorkoutPlan(date: monday, type: .push)
        XCTAssertFalse(plan.isTwoADay)
        XCTAssertNil(plan.secondarySessionType)
        XCTAssertFalse(plan.secondaryCompleted, "secondaryCompleted defaults to false")
    }

    func testSettingSecondaryTypeMakesItATwoADay() {
        let plan = WorkoutPlan(date: monday, type: .push)
        plan.secondarySessionType = .run
        XCTAssertTrue(plan.isTwoADay)
        XCTAssertEqual(plan.secondarySessionType, .run)
        XCTAssertEqual(plan.secondarySessionTypeRaw, WorkoutType.run.rawValue)
    }
}
