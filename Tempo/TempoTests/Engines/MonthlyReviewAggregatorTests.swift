//
// MonthlyReviewAggregatorTests.swift
// Tempo
//
// D4 §17.2 — the contract for every number the Sonnet monthly report is
// allowed to say. The two honesty rules under test: §15.2 (floor-forced skips
// never count against adherence) and §12 G5 (body comp is a robust trend or
// an admitted gap, never a noisy point-to-point delta). Pure — no store.
//

@testable import Tempo
import XCTest

final class MonthlyReviewAggregatorTests: XCTestCase {

    private let cal = Calendar.current

    private func day(_ d: Int, hour: Int = 16) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: d, hour: hour))!
    }

    private func plan(
        day d: Int, type: String = "Push", status: WorkoutStatus = .completed,
        reason: SkipReason? = nil, startHour: Int? = 16,
        tonnage: Double = 5000, rpe: Int? = 7
    ) -> MonthPlanSnapshot {
        MonthPlanSnapshot(
            date: day(d),
            typeDisplayName: type,
            statusRaw: status.rawValue,
            skipReasonRaw: reason?.rawValue,
            startedAt: status == .completed ? startHour.map { day(d, hour: $0) } : nil,
            tonnageKg: status == .completed ? tonnage : 0,
            sessionRPE: status == .completed ? rpe : nil
        )
    }

    private func aggregate(
        plans: [MonthPlanSnapshot] = [],
        body: [MonthBodySample] = [],
        recovery: [MonthRecoverySample] = [],
        prs: [MonthPRSnapshot] = [],
        exercise: AccuracySummary = .empty,
        session: SessionRPEAccuracy = .empty
    ) -> MonthlyReviewData {
        MonthlyReviewAggregator.aggregate(
            monthKey: "2026-06", daysInMonth: 30,
            plans: plans, bodySamples: body, recoverySamples: recovery,
            prs: prs, exerciseAccuracy: exercise, sessionAccuracy: session
        )
    }

    // MARK: - Adherence (§15.2 — the floor never counts against him)

    func testAdherenceExcludesFloorForcedSkips() {
        let plans =
            (1 ... 8).map { plan(day: $0) }
            + [plan(day: 9, status: .skipped, reason: .userSkipped),
               plan(day: 10, status: .skipped, reason: .userSkipped)]
            + (11 ... 13).map { plan(day: $0, status: .skipped, reason: .floorForced) }
        let data = aggregate(plans: plans)
        XCTAssertEqual(data.adherencePct, 80, "8/(8+2) — the 3 floor-forced days are OUT of the denominator")
        XCTAssertEqual(data.userSkipped, 2)
        XCTAssertEqual(data.floorForcedSkips, 3)
    }

    func testAdherenceNilWhenNothingTerminal() {
        let data = aggregate(plans: [plan(day: 1, status: .planned)])
        XCTAssertNil(data.adherencePct, "No denominator → no claim")
        XCTAssertEqual(data.completedTotal, 0)
    }

    // MARK: - Training shape

    func testModalityGroupingAndTypicalHour() {
        let plans = [
            plan(day: 1, type: "Push", startHour: 16),
            plan(day: 2, type: "Push", startHour: 17),
            plan(day: 3, type: "Football", startHour: 20),
        ]
        let data = aggregate(plans: plans)
        XCTAssertEqual(data.completedByModality["Push"], 2)
        XCTAssertEqual(data.completedByModality["Football"], 1)
        XCTAssertEqual(data.typicalStartHour, 17, "Median of 16/17/20")
    }

    func testWeeklyTonnageIsChronological() {
        // June 2026: day 1 falls in an earlier ISO week than day 10.
        let plans = [plan(day: 1, tonnage: 4000), plan(day: 10, tonnage: 6000)]
        let data = aggregate(plans: plans)
        XCTAssertEqual(data.weeklyTonnageKg, [4000, 6000])
        XCTAssertEqual(data.totalTonnageKg, 10000)
    }

    // MARK: - Body comp (§12 G5)

    func testBodyCompBelowMinSamplesIsNilPlusGap() {
        let body = (1 ... 5).map {
            MonthBodySample(date: day($0), weightKg: 80, bodyFatPercent: 15, leanMassKg: 65)
        }
        let data = aggregate(body: body)
        XCTAssertNil(data.weightDeltaKg)
        XCTAssertTrue(data.gaps.contains { $0.contains("5 weigh-ins") },
                      "Thin data must surface as a stated gap, not silence")
    }

    func testBodyCompEndpointSpikeDoesNotBecomeAchievement() {
        // Flat 80kg month; final weigh-in is a +2.5 hydration swing.
        var body = (1 ... 29).map {
            MonthBodySample(date: day($0), weightKg: 80, bodyFatPercent: nil, leanMassKg: nil)
        }
        body.append(MonthBodySample(date: day(30), weightKg: 82.5, bodyFatPercent: nil, leanMassKg: nil))
        let data = aggregate(body: body)
        XCTAssertEqual(data.weightDeltaKg!, 0, accuracy: 0.3,
                       "G5: point-to-point would say +2.5kg; the robust trend must not")
        XCTAssertNil(data.bodyFatDeltaPct, "No fat% samples → nil, not zero")
    }

    // MARK: - Honest gaps (§17.2)

    func testWhoopGapStatedWhenDaysMissing() {
        let recovery = (1 ... 20).map {
            MonthRecoverySample(date: day($0), hrv: 60, rhr: 55, recoveryScore: 70)
        }
        let data = aggregate(recovery: recovery)
        XCTAssertTrue(data.gaps.contains { $0.contains("missing for 10 of 30 days") })
    }

    func testUnratedSessionsGapWhenMajorityUnrated() {
        let plans = (1 ... 4).map { plan(day: $0, rpe: nil) } + [plan(day: 5, rpe: 8)]
        let data = aggregate(plans: plans)
        XCTAssertTrue(data.gaps.contains { $0.contains("4 of 5 sessions have no session-RPE") })
    }

    func testNoCalibrationGapWhenBothSpinesEmpty() {
        let data = aggregate(plans: [plan(day: 1)])
        XCTAssertTrue(data.gaps.contains { $0.contains("cannot judge prescription calibration") })
    }

    // MARK: - Prompt seam

    func testPromptCarriesNumbersGapsAndInterview() {
        let plans = (1 ... 8).map { plan(day: $0) }
            + [plan(day: 9, status: .skipped, reason: .userSkipped),
               plan(day: 10, status: .skipped, reason: .userSkipped)]
        let data = aggregate(plans: plans)
        let interview = MonthInterviewSnapshot(
            wentWell: "consistent gym", struggles: nil,
            goalsNextMonth: "keep streak", chosenEmphasis: "soccer"
        )
        let msg = MonthlyReviewPrompt.userMessage(data: data, interview: interview)
        XCTAssertTrue(msg.contains("- Adherence: 80%"))
        XCTAssertTrue(msg.contains("Push ×8"))
        XCTAssertTrue(msg.contains("weight insufficient data"), "nil delta must read as a gap, never a number")
        XCTAssertTrue(msg.contains("- Went well: consistent gym"))
        XCTAssertTrue(msg.contains("- Struggles/skips: (not answered)"))
        XCTAssertTrue(msg.contains("declared emphasis: soccer"))
        for gap in data.gaps {
            XCTAssertTrue(msg.contains(gap), "Every gap line must reach the prompt verbatim")
        }
    }

    func testPromptOmitsCalibrationLinesWithoutSamples() {
        let msg = MonthlyReviewPrompt.userMessage(data: aggregate(), interview: MonthInterviewSnapshot())
        XCTAssertFalse(msg.contains("Set-level calibration"))
        XCTAssertFalse(msg.contains("Session-level calibration"))
    }

    // MARK: - Schedule window (§17 — month-boundary ritual, not a nag)

    func testDueOnlyInsideTheBoundaryWindow() {
        // June 2026 has 30 days → tail = 28/29/30.
        XCTAssertNil(MonthlyReviewSchedule.dueMonthKey(on: day(10)))
        XCTAssertNil(MonthlyReviewSchedule.dueMonthKey(on: day(27)))
        XCTAssertEqual(MonthlyReviewSchedule.dueMonthKey(on: day(28)), "2026-06")
        XCTAssertEqual(MonthlyReviewSchedule.dueMonthKey(on: day(30)), "2026-06")
    }

    func testGraceDaysReviewThePreviousMonth() {
        let july2 = cal.date(from: DateComponents(year: 2026, month: 7, day: 2))!
        let july5 = cal.date(from: DateComponents(year: 2026, month: 7, day: 5))!
        XCTAssertEqual(MonthlyReviewSchedule.dueMonthKey(on: july2), "2026-06")
        XCTAssertNil(MonthlyReviewSchedule.dueMonthKey(on: july5))
    }

    func testGraceWindowCrossesYearBoundary() {
        let jan2 = cal.date(from: DateComponents(year: 2027, month: 1, day: 2))!
        XCTAssertEqual(MonthlyReviewSchedule.dueMonthKey(on: jan2), "2026-12")
    }

    func testMonthIntervalAndNextMonthStart() {
        let interval = MonthlyReviewSchedule.monthInterval(forKey: "2026-06")!
        XCTAssertEqual(interval.start, cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!)
        XCTAssertEqual(interval.end, cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!)
        XCTAssertEqual(MonthlyReviewSchedule.nextMonthStart(afterKey: "2026-06"), interval.end)
        XCTAssertNil(MonthlyReviewSchedule.monthInterval(forKey: "garbage"))
    }
}
