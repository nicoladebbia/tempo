//
// WhoopPersonalizationTests.swift
// Tempo
//
// Proves the Whoop-export personalization layer (2026-06-09): the quote-aware
// CSV parser, the cycle/workout/journal mappers (unit conversions, activity→
// WorkoutType mapping, zone-percent→minutes), the journal correlation math
// (min-arm + min-delta gates, same-cycle pairing), the floor's illness-TRIAD
// route (two of resp/skin-temp/SpO2 on non-green → SEVERE; one alone is
// noise), and the new prompt lines (consistency, illness signals, Z4+ load,
// PERSONAL PATTERNS).
//

@testable import Tempo
import XCTest

final class WhoopPersonalizationTests: XCTestCase {
    // MARK: - CSV core

    func testQuotedFieldsWithCommasEscapesAndNewlines() {
        let csv = "a,b,c\n1,\"hello, world\",\"line\nbreak \"\"quoted\"\"\"\n"
        let rows = WhoopExportParser.parseCSV(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1], ["1", "hello, world", "line\nbreak \"quoted\""])
    }

    func testTimezoneOffsetParsing() {
        XCTAssertEqual(WhoopExportParser.timeZone(from: "UTC-04:00")?.secondsFromGMT(), -14400)
        XCTAssertEqual(WhoopExportParser.timeZone(from: "UTC+05:30")?.secondsFromGMT(), 19800)
        XCTAssertNil(WhoopExportParser.timeZone(from: "garbage"))
    }

    // MARK: - Cycle mapping (real export header + row)

    private let cycleCSV = """
    Cycle start time,Cycle end time,Cycle timezone,Recovery score %,Resting heart rate (bpm),Heart rate variability (ms),Skin temp (celsius),Blood oxygen %,Day Strain,Energy burned (cal),Max HR (bpm),Average HR (bpm),Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min),Light sleep duration (min),Deep (SWS) duration (min),REM duration (min),Awake duration (min),Sleep need (min),Sleep debt (min),Sleep efficiency %,Sleep consistency %
    2026-06-09 00:43:33,,UTC-04:00,74,51,88,34.11,97.28,,,,,2026-06-09 00:43:33,2026-06-09 08:56:19,79,15.7,436,492,214,105,117,56,452,78,88,49
    2026-06-08 01:02:11,,UTC-04:00,,50,90,34.0,97.0,,,,,,,,,,,,,,,,,,
    """

    func testCycleRowMapsUnitsAndSkipsScorelessDays() {
        let rows = WhoopExportParser.cycles(fromCSV: cycleCSV)
        XCTAssertEqual(rows.count, 1, "The scoreless 06-08 row is skipped — no recovery to import")
        let r = rows[0]
        XCTAssertEqual(r.recoveryScore, 74)
        XCTAssertEqual(r.sleepHours!, 436.0 / 60, accuracy: 0.001, "Asleep minutes → hours")
        XCTAssertEqual(r.sleepDebtHours!, 78.0 / 60, accuracy: 0.001, "Debt minutes → hours")
        XCTAssertEqual(r.skinTemp, 34.11)
        XCTAssertEqual(r.spo2, 97.28)
        XCTAssertEqual(r.consistencyPct, 49)
        XCTAssertEqual(r.deepMin, 105)
        XCTAssertNil(r.dayStrain, "Empty cell → nil, not 0")
    }

    // MARK: - Workout mapping

    private let workoutCSV = """
    Cycle start time,Cycle end time,Cycle timezone,Workout start time,Workout end time,Duration (min),Activity name,Activity Strain,Energy burned (cal),Max HR (bpm),Average HR (bpm),HR Zone 1 %,HR Zone 2 %,HR Zone 3 %,HR Zone 4 %,HR Zone 5 %,GPS enabled
    2026-06-09 00:43:33,,UTC-04:00,2026-06-09 16:00:00,2026-06-09 17:30:00,90,Soccer,14.2,800,190,150,10,20,30,30,10,true
    """

    func testWorkoutRowMapsActivityAndZones() {
        let rows = WhoopExportParser.workouts(fromCSV: workoutCSV)
        XCTAssertEqual(rows.count, 1)
        let w = rows[0]
        XCTAssertEqual(w.workoutType, "football", "Soccer maps onto the WorkoutType raw value")
        XCTAssertEqual(w.zoneMinutes?[3] ?? 0, 27, accuracy: 0.001, "30% of 90min = 27 Z4 minutes")
        XCTAssertEqual(w.zoneMinutes?[4] ?? 0, 9, accuracy: 0.001)
        XCTAssertEqual(w.strain, 14.2)
    }

    func testActivityNameMapping() {
        XCTAssertEqual(WhoopExportParser.workoutTypeRaw(forActivity: "Soccer"), "football")
        XCTAssertEqual(WhoopExportParser.workoutTypeRaw(forActivity: "Swimming"), "pool")
        XCTAssertEqual(WhoopExportParser.workoutTypeRaw(forActivity: "Weightlifting"), "full_body")
        XCTAssertEqual(WhoopExportParser.workoutTypeRaw(forActivity: "Padel"), "padel", "Unmapped names pass through lowercased")
    }

    // MARK: - Journal correlations

    func testCorrelationsRespectGatesAndPairing() {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        var journal: [WhoopExportParser.JournalRow] = []
        var recovery: [Date: Double] = [:]
        // 25 yes-days at recovery 50, 25 no-days at 65 → delta −15, reportable.
        // Plus an under-sampled question that must be filtered out.
        for i in 0 ..< 50 {
            let day = cal.date(byAdding: .day, value: -i, to: base)!
            let yes = i % 2 == 0
            recovery[day] = yes ? 50 : 65
            journal.append(.init(day: day, question: "Have any alcoholic drinks?", answeredYes: yes))
            if i < 5 {
                journal.append(.init(day: day, question: "Rare question?", answeredYes: yes))
            }
        }
        let result = WhoopExportParser.correlations(journal: journal, recoveryByDay: recovery)
        XCTAssertEqual(result.count, 1, "Under-sampled questions never report")
        XCTAssertEqual(result[0].question, "Have any alcoholic drinks?")
        XCTAssertEqual(result[0].delta, -15, accuracy: 0.001)
        XCTAssertEqual(result[0].yesCount, 25)
    }

    // MARK: - Floor illness triad

    private func picture(
        recovery: Double = 55,
        respDelta: Double? = 0,
        skinTempDelta: Double? = nil,
        spo2: Double? = nil
    ) -> ReadinessPicture {
        var p = ReadinessPicture(
            recoveryScore: recovery,
            hrv: 60, rhr: 50, respRate: 14, sleepHours: 8,
            sleepDebt: 0, dayStrain: 10, deepSleepMin: 90,
            hrvZScore: 0, hrvTrend7d: .flat,
            rhrDeltaBpm: 0, rhrZScore: 0,
            respDeltaBrMin: respDelta, acuteChronicStrainRatio: 1.0,
            yesterdaySessions: [], weightKg: 80, bodyFatPct: 12, leanMassKg: 68,
            checkIn: nil, daysUntilNextMatch: nil,
            validBaselineSampleCount: 30, historyDayCount: 30
        )
        p.skinTempDeltaC = skinTempDelta
        p.spo2 = spo2
        return p
    }

    func testTwoIllnessSignalsOnYellowIsSevere() {
        // Warm skin + low SpO2, NORMAL breathing — the case the resp-only route misses.
        let p = picture(recovery: 55, respDelta: 0, skinTempDelta: 1.2, spo2: 93)
        XCTAssertTrue(TrainingSafetyFloor.isSevere(p))
    }

    func testOneIllnessSignalAloneIsNotSevere() {
        XCTAssertFalse(TrainingSafetyFloor.isSevere(picture(skinTempDelta: 1.5)),
                       "Skin temp alone is hydration/sensor noise — not a veto")
        XCTAssertFalse(TrainingSafetyFloor.isSevere(picture(spo2: 93)))
    }

    func testTriadOnGreenDoesNotFire() {
        let p = picture(recovery: 80, skinTempDelta: 1.2, spo2: 93)
        XCTAssertFalse(TrainingSafetyFloor.isSevere(p), "Green recovery gates the illness routes")
    }

    // MARK: - Prompt lines

    func testPromptSurfacesConsistencyOnlyWhenBad() {
        let bad = ReadinessAssembler.assemble(
            history: [], today: DailyRecoverySnapshot(
                date: Date(), recoveryScore: 70, hrv: nil, rhr: nil, respRate: nil,
                sleepHours: 7, sleepDebt: 1, strain: nil, deepSleepMin: nil,
                skinTemp: nil, spo2: nil, sleepConsistency: 49
            )
        )
        XCTAssertTrue(DailyCoachPrompt.userMessage(for: bad).contains("Sleep consistency: 49%"))

        let fine = ReadinessAssembler.assemble(
            history: [], today: DailyRecoverySnapshot(
                date: Date(), recoveryScore: 70, hrv: nil, rhr: nil, respRate: nil,
                sleepHours: 7, sleepDebt: 1, strain: nil, deepSleepMin: nil,
                skinTemp: nil, spo2: nil, sleepConsistency: 85
            )
        )
        XCTAssertFalse(DailyCoachPrompt.userMessage(for: fine).contains("Sleep consistency"))
    }

    func testPromptCarriesPersonalPatternsAndYesterdayIntensity() {
        var p = picture()
        p.habitPatterns = ["Have any alcoholic drinks? → −7 recovery pts on yes-days (n=120/200, his own data)"]
        var message = DailyCoachPrompt.userMessage(for: p)
        XCTAssertTrue(message.contains("PERSONAL PATTERNS"))
        XCTAssertTrue(message.contains("alcoholic"))

        let yesterday = YesterdaySession(type: "football", strain: 14, durationMin: 90, avgHR: 150, hardMinutes: 36)
        p = picture()
        p = ReadinessAssembler.assemble(
            history: [], today: nil,
            yesterdaySessions: [ActivitySnapshot(workoutType: "football", strain: 14, durationMinutes: 90,
                                                 averageHeartRate: 150, hardMinutes: 36)]
        )
        message = DailyCoachPrompt.userMessage(for: p)
        XCTAssertTrue(message.contains("36min Z4+"), "Yesterday's true intensity reaches the prompt")
        XCTAssertEqual(yesterday.hardMinutes, 36)
    }
}
