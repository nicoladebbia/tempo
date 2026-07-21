//
// EmphasisPeriodizationTests.swift
// Tempo
//
// Proves the emphasis-aware deterministic week (§14 Decision 1, wired
// 2026-06-09): a soccer block visibly re-shapes SPARE days — exactly one
// conditioning day (never on T-1 of a match/football day), every other spare
// becomes an easy pool swim — while gym days stay put (§12: strength held at
// maintenance, never fewer lifting days). Physique must remain byte-identical
// to the pre-emphasis engine. Also pins the §14 label split: recurring
// football weekdays say "Football day"; only a DATED match says "Match day".
//

@testable import Tempo
import XCTest

final class EmphasisPeriodizationTests: XCTestCase {
    private let engine = TrainingEngine()
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// A fixed Monday (2023-11-13) as week start.
    private var monday: Date {
        let base = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 (Tue)
        return cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: base))!
    }

    private func week(
        emphasis: BlockEmphasis,
        footballDays: ActiveDays = ActiveDays(rawValue: 0),
        matchDayKeys: Set<Date> = []
    ) -> [WorkoutPlan] {
        engine.generateWeekPlan(
            startDate: monday,
            recoveryScores: [:], // no data → green default everywhere
            footballDays: footballDays,
            // .custom = 3 training days → Thu/Fri/Sat are SPARE days, which is
            // what the emphasis logic re-shapes (and Nicola's real split).
            split: .custom,
            matchDayKeys: matchDayKeys,
            emphasis: emphasis
        )
    }

    /// Sunday-only football (Foundation weekday 1 → bit 1<<6 in the Mon-first
    /// mask used by UserSettings? — built via ActiveDays helper to stay
    /// convention-proof).
    private var sundayFootball: ActiveDays {
        // Find the bit that makes Sunday active by probing all 7 bits.
        for bit in 0 ..< 7 {
            let days = ActiveDays(rawValue: 1 << bit)
            if days.isActive(on: 1) { return days } // 1 = Sunday
        }
        XCTFail("No ActiveDays bit maps to Sunday")
        return ActiveDays(rawValue: 0)
    }

    // MARK: - Physique = pre-emphasis behavior exactly

    func testPhysiqueWeekHasEasyCrossTrainingButNoHardConditioning() {
        // §14 REVISED (auto-variety, Slice 1): physique spare days are no longer
        // idle mobility/rest — they become EASY cross-training (swim / easy run)
        // so every week is varied. The HARD conditioning day stays soccer-
        // emphasis-only, so physique still contains zero conditioning.
        let plans = week(emphasis: .physique)
        XCTAssertFalse(plans.contains { $0.type == .conditioning },
                       "Hard conditioning is soccer-emphasis only")
        XCTAssertTrue(plans.contains { $0.type == .pool || $0.type == .run },
                      "Spare days become easy cross-training, not idle mobility/rest")
        XCTAssertFalse(plans.contains { $0.type == .mobility && $0.notes == "Active recovery" },
                       "Spare days are cross-training now, not generic active recovery")
    }

    func testSpareWeekdaysAreCrossTrainingAndSundayStaysRest() {
        // Slice 1 invariant: no idle spare weekdays — each becomes a cross-
        // training modality — while Sunday is preserved as a full rest day.
        let plans = week(emphasis: .physique)
        for p in plans where !p.type.isGymWorkout && p.type != .football {
            let weekday = cal.component(.weekday, from: p.date)
            if weekday == 1 { // Sunday
                XCTAssertEqual(p.type, .rest, "Sunday stays a full rest day")
            } else {
                XCTAssertNotEqual(p.type, .rest, "Spare weekdays are cross-training, never idle rest")
                XCTAssertTrue([.pool, .run, .conditioning, .mobility].contains(p.type),
                              "A spare weekday resolves to a cross-training modality")
            }
        }
    }

    // MARK: - Soccer re-shapes spare days

    func testSoccerWeekAddsOneConditioningAndPool() {
        let plans = week(emphasis: .soccer)
        XCTAssertEqual(plans.filter { $0.type == .conditioning }.count, 1,
                       "Exactly ONE conditioning day per week — §12, not a second hard day")
        XCTAssertTrue(plans.contains { $0.type == .pool }, "Remaining spares become easy pool swims")
    }

    func testSoccerWeekKeepsGymDayCount() {
        let gymDays: ([WorkoutPlan]) -> Int = { $0.filter { $0.type.isGymWorkout }.count }
        XCTAssertEqual(
            gymDays(week(emphasis: .physique)), gymDays(week(emphasis: .soccer)),
            "§12 — strength held at maintenance: soccer emphasis never cuts lifting days"
        )
    }

    func testConditioningNeverLandsOnTMinus1() {
        let plans = week(emphasis: .soccer, footballDays: sundayFootball)
        let saturday = cal.date(byAdding: .day, value: 5, to: monday)!
        let satPlan = plans.first { cal.isDate($0.date, inSameDayAs: saturday) }
        XCTAssertNotNil(satPlan)
        XCTAssertNotEqual(satPlan?.type, .conditioning,
                          "T-1 of Sunday football must not be high-intensity conditioning")
        if let sat = satPlan, !sat.type.isGymWorkout, sat.type != .football {
            XCTAssertEqual(sat.type, .pool, "A spare T-1 becomes the easy swim, not conditioning")
        }
        XCTAssertEqual(plans.filter { $0.type == .conditioning }.count, 1,
                       "The conditioning day still exists — just not on T-1")
    }

    // MARK: - §14 label split (the recurring-vs-dated conflation fix)

    func testRecurringFootballDaySaysFootballDay() {
        let plans = week(emphasis: .physique, footballDays: sundayFootball)
        let sunday = cal.date(byAdding: .day, value: 6, to: monday)!
        let sunPlan = plans.first { cal.isDate($0.date, inSameDayAs: sunday) }
        XCTAssertEqual(sunPlan?.type, .football)
        XCTAssertEqual(sunPlan?.notes, "Football day", "Recurring weekday is cadence, not a fixture")
    }

    func testDatedMatchSaysMatchDay() {
        let wednesday = cal.date(byAdding: .day, value: 2, to: monday)!
        let plans = week(emphasis: .physique, matchDayKeys: [cal.startOfDay(for: wednesday)])
        let wedPlan = plans.first { cal.isDate($0.date, inSameDayAs: wednesday) }
        XCTAssertEqual(wedPlan?.type, .football)
        XCTAssertEqual(wedPlan?.notes, "Match day", "Only a DATED fixture earns the match label")
    }
}
