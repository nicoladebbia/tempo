//
// ReadinessAssemblerTests.swift
// Tempo
//
// Proves the assembler turns real stored history into a correct ReadinessPicture,
// and degrades safely on partial/empty history (§4.1 exit + §6.3 cold-start). Pure.
//

@testable import Tempo
import XCTest

final class ReadinessAssemblerTests: XCTestCase {

    private func day(_ offset: Int, recovery: Double = 70, hrv: Double? = 60, rhr: Double? = 50, resp: Double? = 14, strain: Double? = 10) -> DailyRecoverySnapshot {
        DailyRecoverySnapshot(
            date: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400),
            recoveryScore: recovery, hrv: hrv, rhr: rhr, respRate: resp,
            sleepHours: 7.5, sleepDebt: 0, strain: strain, deepSleepMin: 90
        )
    }

    /// 30 days of varied-but-healthy history, oldest→newest.
    private func healthyHistory() -> [DailyRecoverySnapshot] {
        (0 ..< 30).map { i in day(i, hrv: 60 + Double(i % 5), rhr: 50 + Double(i % 3), strain: 10 + Double(i % 4)) }
    }

    // MARK: - Full history → trends populate

    func testFullHistoryPopulatesTrends() {
        let history = healthyHistory()
        let today = day(30, recovery: 72, hrv: 58, rhr: 52, strain: 11)
        let p = ReadinessAssembler.assemble(history: history, today: today)

        XCTAssertEqual(p.recoveryScore, 72)
        XCTAssertEqual(p.hrv, 58)
        XCTAssertNotNil(p.hrvZScore, "30 days of HRV → z-score computes")
        XCTAssertNotNil(p.rhrDeltaBpm, "30 days of RHR → bpm delta computes")
        XCTAssertNotNil(p.acuteChronicStrainRatio, "30 days of strain → ACWR computes")
        XCTAssertGreaterThanOrEqual(p.validBaselineSampleCount, 14)
        XCTAssertTrue(p.hasBaselineForFloor)
        XCTAssertTrue(p.hasBaselineForBrain)
    }

    // MARK: - Cold-start: short history → trends nil, gates false, no crash

    func testColdStartShortHistoryDisablesRawRoutes() {
        let history = (0 ..< 8).map { day($0) } // 8 days < 14
        let today = day(8, recovery: 65)
        let p = ReadinessAssembler.assemble(history: history, today: today)

        XCTAssertNil(p.hrvZScore, "Below 14 valid → no z-score")
        XCTAssertNil(p.rhrDeltaBpm, "Below 14 valid → no RHR delta")
        XCTAssertFalse(p.hasBaselineForFloor, "Floor degrades to Route A")
        XCTAssertFalse(p.hasBaselineForBrain, "Brain stays in SIMPLE mode")
        XCTAssertEqual(p.recoveryScore, 65, "Recovery score still surfaced (Route A works cold)")
    }

    func testEmptyHistoryDoesNotCrash() {
        let p = ReadinessAssembler.assemble(history: [], today: nil)
        XCTAssertEqual(p.recoveryScore, 0)
        XCTAssertNil(p.hrvZScore)
        XCTAssertEqual(p.historyDayCount, 0)
        XCTAssertFalse(p.hasBaselineForFloor)
    }

    // MARK: - Missing HRV days don't inflate the sample count falsely

    func testValidSampleCountCountsOnlyNonNil() {
        // 30 calendar days but HRV present only on 12 → below the floor gate.
        let history = (0 ..< 30).map { i in
            day(i, hrv: i < 12 ? 60 : nil, rhr: i < 12 ? 50 : nil)
        }
        let p = ReadinessAssembler.assemble(history: history, today: day(30, hrv: nil, rhr: nil))
        XCTAssertEqual(p.validBaselineSampleCount, 12)
        XCTAssertFalse(p.hasBaselineForFloor, "12 valid < 14 → raw routes disabled even with 30 calendar days")
    }

    // MARK: - Yesterday sessions + body-comp + check-in surface through

    func testYesterdaySessionsAndBodyCompSurface() {
        let p = ReadinessAssembler.assemble(
            history: healthyHistory(),
            today: day(30),
            yesterdaySessions: [ActivitySnapshot(workoutType: "legs", strain: 14, durationMinutes: 70, averageHeartRate: 140)],
            bodyComp: BodyCompSnapshot(weightKg: 80, bodyFatPercent: 12, leanMassKg: 68),
            checkIn: MorningCheckInSnapshot(mood: 4, stress: 3, soreness: ["quads": 6])
        )
        XCTAssertEqual(p.yesterdaySessions.count, 1)
        XCTAssertEqual(p.yesterdaySessions.first?.type, "legs")
        XCTAssertEqual(p.weightKg, 80)
        XCTAssertEqual(p.checkIn?.mood, 4)
    }

    // MARK: - The assembled picture flows into the floor without crashing

    func testAssembledPictureClassifiesInFloor() {
        // A cooked day assembled from real history → floor should see SEVERE.
        let history = healthyHistory()
        let cookedToday = day(30, recovery: 28, hrv: 40, rhr: 60, strain: 18)
        let p = ReadinessAssembler.assemble(history: history, today: cookedToday)
        XCTAssertEqual(TrainingSafetyFloor.classifyFloorTier(p), .severe, "Red recovery from real assembly → SEVERE")
    }
}
