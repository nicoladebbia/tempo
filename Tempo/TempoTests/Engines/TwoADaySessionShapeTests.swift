//
// TwoADaySessionShapeTests.swift
// Tempo
//
// Requirement (b), Slice 2: once the week generator marks a gym day as a
// two-a-day (WorkoutPlan.secondarySessionType set), the deterministic daily
// prescription must emit it as TWO time-separated parts (lift + easy cardio) so
// the Today card renders both — UNLESS the morning's readiness is compromised,
// in which case the §2 ease gate DROPS the second session. Pins that the two
// parts are ≥6h apart (clears the safety floor's composite rule) and that a
// plain gym day stays a single part.
//

@testable import Tempo
import XCTest

@MainActor
final class TwoADaySessionShapeTests: XCTestCase {
    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    /// Full-field readiness builder; recovery/acwr/hrvTrend drive the ease gate.
    private func picture(recovery: Double, acwr: Double? = 1.0, hrvTrend: TrendDirection = .flat) -> ReadinessPicture {
        ReadinessPicture(
            recoveryScore: recovery, hrv: 60, rhr: 50, respRate: 14, sleepHours: 8,
            sleepDebt: 0, dayStrain: 10, deepSleepMin: 90,
            hrvZScore: 0, hrvTrend7d: hrvTrend, rhrDeltaBpm: 0, rhrZScore: 0,
            respDeltaBrMin: 0, acuteChronicStrainRatio: acwr, yesterdaySessions: [],
            weightKg: 80, bodyFatPct: 12, leanMassKg: 68, checkIn: nil,
            daysUntilNextMatch: nil, validBaselineSampleCount: 30, historyDayCount: 30
        )
    }

    private var today: Date { Date() }

    // MARK: - Composition

    func testTwoADayGymDayEmitsTwoTimeSeparatedParts() {
        let vm = makeVM()
        let plan = WorkoutPlan(date: today, type: .push)
        plan.secondarySessionType = .run
        let session = vm.deterministicCandidate(for: plan, readiness: picture(recovery: 80))
        XCTAssertTrue(session.isComposite, "A two-a-day should prescribe two parts")
        XCTAssertEqual(session.parts.count, 2)
        // Part 1 is the lift, part 2 the easy cardio.
        XCTAssertTrue(session.parts[0].blocks.contains { $0.kind == .gym }, "First part is the lift")
        XCTAssertTrue(session.parts[1].blocks.contains { $0.kind == .run }, "Second part is the cardio")
    }

    func testTheTwoPartsAreAtLeastSixHoursApart() {
        let vm = makeVM()
        let plan = WorkoutPlan(date: today, type: .pull)
        plan.secondarySessionType = .pool
        let session = vm.deterministicCandidate(for: plan, readiness: picture(recovery: 80))
        let mins = session.parts.compactMap(\.scheduledMin).sorted()
        XCTAssertEqual(mins.count, 2, "Both parts must be timed, or they'd merge into one")
        XCTAssertGreaterThanOrEqual(mins[1] - mins[0], 6 * 60,
                                    "Parts must be ≥6h apart to clear the floor's composite-day rule")
    }

    func testSecondSessionModalityMatchesThePlan() {
        let vm = makeVM()
        let runPlan = WorkoutPlan(date: today, type: .upper)
        runPlan.secondarySessionType = .run
        XCTAssertTrue(vm.deterministicCandidate(for: runPlan, readiness: picture(recovery: 80))
            .blocks.contains { $0.kind == .run })

        let poolPlan = WorkoutPlan(date: today, type: .push)
        poolPlan.secondarySessionType = .pool
        XCTAssertTrue(vm.deterministicCandidate(for: poolPlan, readiness: picture(recovery: 80))
            .blocks.contains { $0.kind == .pool })
    }

    // MARK: - The ease drop

    func testLowReadinessMorningDropsTheSecondSession() {
        let vm = makeVM()
        let plan = WorkoutPlan(date: today, type: .push)
        plan.secondarySessionType = .run
        // Recovery below 50 eases → the second session is dropped, lift stays.
        let session = vm.deterministicCandidate(for: plan, readiness: picture(recovery: 42))
        XCTAssertFalse(session.isComposite, "A compromised morning drops the second session")
        XCTAssertEqual(session.parts.count, 1)
        XCTAssertTrue(session.blocks.contains { $0.kind == .gym }, "The lift itself is never dropped")
        XCTAssertFalse(session.blocks.contains { $0.kind == .run }, "The cardio second session is gone")
    }

    func testAcuteLoadSpikeAlsoDropsTheSecondSession() {
        let vm = makeVM()
        let plan = WorkoutPlan(date: today, type: .pull)
        plan.secondarySessionType = .pool
        // Recovery looks okay (70) but a 1.7 acute:chronic ratio eases.
        let session = vm.deterministicCandidate(for: plan, readiness: picture(recovery: 70, acwr: 1.7))
        XCTAssertFalse(session.isComposite, "An acute load spike drops the second session even on middling recovery")
    }

    // MARK: - No regression on plain gym days

    func testPlainGymDayStaysASinglePart() {
        let vm = makeVM()
        let plan = WorkoutPlan(date: today, type: .legs) // no secondary set
        let session = vm.deterministicCandidate(for: plan, readiness: picture(recovery: 80))
        XCTAssertFalse(session.isComposite, "A day with no secondary session is a single part, unchanged")
        XCTAssertEqual(session.parts.count, 1)
    }
}
