//
// ReadinessAssembler.swift
// Tempo
//
// Assembles a real ReadinessPicture from stored history (docs/INTELLIGENT_TRAINING_SYSTEM.md §4.1).
// Pure: takes already-FETCHED arrays (no SwiftData query, no network) so it's
// fully unit-testable. The ViewModel does the fetch; this does the math via
// ReadinessTrendMath. Replaces D0's synthetic-authored trend fields with real
// derivation from the 30-day DailyRecovery backfill.
//
// Inputs (caller fetches):
//   • history: trailing DailyRecovery sorted oldest→newest (today LAST or absent)
//   • today: today's DailyRecovery (the latest sync), or nil if not synced
//   • yesterdaySessions: yesterday's ActivitySession rows (surfaced, §4.1)
//   • bodyComp: latest BodyCompositionData (Withings via HealthKit), or nil
//   • checkIn: today's MorningCheckIn snapshot, or nil
//   • daysUntilNextMatch: from the match calendar (D3), or nil
//

import Foundation

enum ReadinessAssembler {

    /// Window sizes (§6.1). Trailing N valid days.
    static let baselineWindow = 30
    static let acuteWindow = 7
    static let strainWindow = 30

    /// Build the picture. `history` is chronological (oldest→newest) and SHOULD
    /// include the trailing ~30 days; `today` is the most recent day's record.
    static func assemble(
        history: [DailyRecoverySnapshot],
        today: DailyRecoverySnapshot?,
        yesterdaySessions: [ActivitySnapshot] = [],
        bodyComp: BodyCompSnapshot? = nil,
        checkIn: MorningCheckInSnapshot? = nil,
        daysUntilNextMatch: Int? = nil
    ) -> ReadinessPicture {
        // The baseline windows exclude today (deviation is today-vs-history).
        let baseline = Array(history.suffix(baselineWindow))
        let acute = Array(history.suffix(acuteWindow))

        let hrvBaseline = baseline.map(\.hrv)
        let hrvAcute = acute.map(\.hrv)
        let rhrBaseline = baseline.map(\.rhr)
        let respBaseline = baseline.map(\.respRate)
        let strainSeries = history.suffix(strainWindow).map(\.strain)

        let hrvZ = ReadinessTrendMath.hrvZScore(recentLnInput: hrvAcute, baselineInput: hrvBaseline)
        let hrvTrend = ReadinessTrendMath.trend7d(hrvAcute)
        let rhrDelta = ReadinessTrendMath.deviation(today: today?.rhr, baselineInput: rhrBaseline)
        let rhrZ = ReadinessTrendMath.zScore(today: today?.rhr, baselineInput: rhrBaseline)
        let respDelta = ReadinessTrendMath.deviation(today: today?.respRate, baselineInput: respBaseline)
        let acwr = ReadinessTrendMath.acuteChronicRatio(strainSeries: Array(strainSeries))

        // Valid-sample counts gate the floor (≥14) and brain (≥30) cold-starts.
        let validHrvRhr = baseline.filter { $0.hrv != nil || $0.rhr != nil }.count
        let historyDays = history.count

        return ReadinessPicture(
            recoveryScore: today?.recoveryScore ?? 0,
            hrv: today?.hrv,
            rhr: today?.rhr,
            respRate: today?.respRate,
            sleepHours: today?.sleepHours,
            sleepDebt: today?.sleepDebt,
            dayStrain: today?.strain,
            deepSleepMin: today?.deepSleepMin,
            hrvZScore: hrvZ,
            hrvTrend7d: hrvTrend,
            rhrDeltaBpm: rhrDelta,
            rhrZScore: rhrZ,
            respDeltaBrMin: respDelta,
            acuteChronicStrainRatio: acwr,
            yesterdaySessions: yesterdaySessions.map {
                YesterdaySession(type: $0.workoutType, strain: $0.strain, durationMin: $0.durationMinutes, avgHR: $0.averageHeartRate)
            },
            weightKg: bodyComp?.weightKg,
            bodyFatPct: bodyComp?.bodyFatPercent,
            leanMassKg: bodyComp?.leanMassKg,
            checkIn: checkIn,
            daysUntilNextMatch: daysUntilNextMatch,
            validBaselineSampleCount: validHrvRhr,
            historyDayCount: historyDays
        )
    }
}

// MARK: - Input snapshots (decouple the pure assembler from @Model types)

/// The fields the assembler needs from a DailyRecovery row. The ViewModel maps
/// @Model → this; keeps ReadinessAssembler pure and testable without SwiftData.
struct DailyRecoverySnapshot: Equatable, Sendable {
    let date: Date
    let recoveryScore: Double
    let hrv: Double?
    let rhr: Double?
    let respRate: Double?
    let sleepHours: Double?
    let sleepDebt: Double?
    let strain: Double?
    let deepSleepMin: Int?
}

/// The fields the assembler needs from an ActivitySession row.
struct ActivitySnapshot: Equatable, Sendable {
    let workoutType: String
    let strain: Double?
    let durationMinutes: Double?
    let averageHeartRate: Double?
}

/// The fields the assembler needs from HealthKit body composition.
struct BodyCompSnapshot: Equatable, Sendable {
    let weightKg: Double?
    let bodyFatPercent: Double?
    let leanMassKg: Double?
}
