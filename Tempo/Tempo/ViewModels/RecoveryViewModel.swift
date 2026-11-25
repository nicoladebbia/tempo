//
// RecoveryViewModel.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - RecoveryLoadState

enum RecoveryLoadState: Equatable {
    case loading
    case loaded
    case error(String)
}

// MARK: - RecoveryViewModel

// Per MODULE_RECOVERY.md Sections 4-7 and BUILD_PLAN.md Step 8.2.

@Observable
@MainActor
final class RecoveryViewModel {
    // MARK: - State

    var loadState: RecoveryLoadState = .loading
    /// Day, Week or Month: the one switch on the page.
    var selectedRange: RecoveryRange = .day
    /// Month can reach back 90 days instead of 30.
    var monthShowsQuarter = false

    /// How far back the charts and averages reach. Day reads like Week for the
    /// few numbers that borrow a trend (the vitals sheet).
    var selectedTrendRange: TrendRange {
        switch selectedRange {
        case .day, .week: .week
        case .month: monthShowsQuarter ? .quarter : .month
        }
    }

    // MARK: - Today's Data

    var todayRecovery: DailyRecovery?
    var todayPrescription: DailyPrescription?

    // MARK: - Historical Data (for charts)

    var recentRecoveries: [DailyRecovery] = []
    var insights: [RecoveryInsight] = []

    // MARK: - Dependencies

    private let whoop: any WhoopServiceProtocol
    private let recoveryEngine: any RecoveryEngineProtocol
    private let calendar: any CalendarServiceProtocol

    /// Serializes refresh passes so no two run concurrently. Two overlapping
    /// runs each upsert today's DailyRecovery from a PRE-save snapshot — the
    /// second's `buildDailyRecovery` fetch (line ~1130) can't see the first's
    /// un-saved insert → a duplicate row for the same day + the SwiftData
    /// relationship assertion the insert comment already fears + memory pile-up.
    /// A Task handle (not a bool) so `forceRefresh` can AWAIT the in-flight pass
    /// and then run its own instead of silently dropping the user's pull.
    private var refreshInFlight: Task<Void, Never>?

    init(
        whoop: any WhoopServiceProtocol,
        recoveryEngine: any RecoveryEngineProtocol,
        calendar: any CalendarServiceProtocol
    ) {
        self.whoop = whoop
        self.recoveryEngine = recoveryEngine
        self.calendar = calendar
    }

    // MARK: - Refresh

    // Per MODULE_RECOVERY.md Section 4 — Pull-to-refresh

    /// Pull-to-refresh entry point: drops the Whoop in-memory cache so the
    /// user-initiated refresh actually hits the network instead of returning
    /// the value cached during the most-recent Dashboard load.
    ///
    /// The user explicitly asked for fresh data, so this NEVER drops: it waits
    /// for any in-flight pass to settle, then runs a guaranteed pass AFTER the
    /// cache is invalidated. (Coalescing it away — the naive shared guard —
    /// would leave the post-invalidation fetch unexecuted and the pull would
    /// silently no-op.)
    func forceRefresh(modelContext: ModelContext) async {
        await whoop.invalidateCache()
        await refreshInFlight?.value
        await runRefresh(modelContext: modelContext)
    }

    /// On-appear / coalescing entry point. If a refresh is already running,
    /// await it and return rather than starting a concurrent one (that in-flight
    /// pass produces the same fresh data). Only the duplicate-row race matters
    /// here; the running pass satisfies this caller.
    func refresh(modelContext: ModelContext) async {
        if let inFlight = refreshInFlight {
            await inFlight.value
            return
        }
        await runRefresh(modelContext: modelContext)
    }

    /// Runs one refresh pass behind `refreshInFlight` so callers can serialize
    /// on it. The starter (the call that actually created the task) is the only
    /// one that clears the handle, and only if it hasn't been replaced.
    private func runRefresh(modelContext: ModelContext) async {
        let task = Task { @MainActor in
            await self.performRefresh(modelContext: modelContext)
        }
        refreshInFlight = task
        await task.value
        if refreshInFlight == task { refreshInFlight = nil }
    }

    private func performRefresh(modelContext: ModelContext) async {
        loadState = .loading

        let today = Date()

        // Fetch Whoop data only when connected to a real account — this path
        // persists today's DailyRecovery, so demo numbers must never enter it.
        let recoveryData: WhoopRecoveryData?
        let sleepData: WhoopSleepData?
        let cycleData: WhoopCycleData?
        let connectedToRealData = whoop.providesRealData
        if connectedToRealData {
            recoveryData = try? await whoop.fetchRecovery(for: today)
            sleepData = try? await whoop.fetchSleep(for: today)
            cycleData = try? await whoop.fetchCycle(for: today)
        } else {
            recoveryData = nil
            sleepData = nil
            cycleData = nil
        }

        // Build or update DailyRecovery
        let recovery = buildDailyRecovery(
            date: today,
            recoveryData: recoveryData,
            sleepData: sleepData,
            cycleData: cycleData,
            modelContext: modelContext
        )

        // Insert recovery into context BEFORE generating prescription
        // to avoid SwiftData relationship assertion when setting inverse
        modelContext.insert(recovery)

        // Calculate sleep debt from past 7 days (Task 3)
        let sleepDebtStart = Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today
        let sleepDebtDescriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date >= sleepDebtStart },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let recentForDebt = (try? modelContext.fetch(sleepDebtDescriptor)) ?? []
        let sleepTarget = recovery.sleepNeededBaseline ?? 8.0
        let recentSleepHours = recentForDebt.compactMap(\.sleepHours)
        let computedDebt = recoveryEngine.calculateSleepDebt(
            recentSleep: recentSleepHours,
            target: sleepTarget
        )
        recovery.sleepDebt = computedDebt

        // Get calendar events for prescription context
        let endDate = Calendar.current.date(byAdding: .day, value: 2, to: today) ?? today
        let events = await (try? calendar.fetchEvents(
            for: DateInterval(start: today, end: endDate)
        )) ?? []

        // Generate prescription (without relationship — set after insert)
        let prescription = recoveryEngine.generatePrescription(
            recovery: recovery,
            schedule: events
        )

        // Re-stamp hydration with the one water target every screen shows (Today, the Fuel
        // water card, the coach): the engine has no store access, so it cannot know the user's
        // real weight, today's logged activity or today's WorkoutPlan. Today's recovery row
        // was inserted above, so the target adjusts by this very reading.
        prescription.hydrationTargetMl = DailyNutritionTargets.todayWaterTargetMl(in: modelContext, now: today)

        // Insert prescription, then link relationship
        modelContext.insert(prescription)
        prescription.dailyRecovery = recovery

        // Inject anomaly-based warnings into prescription (Task 4)
        // We need recentRecoveries loaded first for 7-day averages,
        // so we'll add anomaly warnings after the full data load below.

        var saveFailed = false
        do {
            try modelContext.save()
        } catch {
            saveFailed = true
        }

        // Seed historical records from Whoop batch data (fills trends on first launch).
        // Only creates new records for dates that don't already exist in the database.
        if whoop.providesRealData {
            // One-time 30-day historical backfill on first successful connect.
            // No-op once WhoopConnection.didBackfill is set.
            await backfillIfNeeded(modelContext: modelContext)

            let todayStart = Calendar.current.startOfDay(for: today)
            let recoveryBatch = await (try? whoop.fetchRecoveryBatch(for: today)) ?? []
            let sleepBatch = await (try? whoop.fetchSleepBatch(for: today)) ?? []

            for histRecovery in recoveryBatch {
                let histDate = Calendar.current.startOfDay(for: histRecovery.date)
                guard histDate != todayStart else {
                    continue
                } // today already handled

                // Check if record already exists — skip if so to avoid SwiftData conflicts
                let checkDescriptor = FetchDescriptor<DailyRecovery>(
                    predicate: #Predicate { $0.date == histDate }
                )
                if (try? modelContext.fetchCount(checkDescriptor)) ?? 0 > 0 {
                    continue
                }

                let matchingSleep = sleepBatch.first { Calendar.current.startOfDay(for: $0.date) == histDate }
                let histDaily = DailyRecovery(
                    date: histDate,
                    recoveryScore: histRecovery.score,
                    hrvRmssd: histRecovery.hrvRmssd,
                    restingHR: histRecovery.restingHeartRate,
                    spo2: histRecovery.spo2,
                    skinTemp: histRecovery.skinTemp,
                    sleepHours: matchingSleep?.totalHours,
                    sleepScore: matchingSleep?.sleepScore,
                    sleepEfficiency: matchingSleep?.sleepEfficiency,
                    sleepConsistency: matchingSleep?.sleepConsistency,
                    deepSleepMin: matchingSleep?.deepSleepMinutes,
                    remSleepMin: matchingSleep?.remSleepMinutes,
                    lightSleepMin: matchingSleep?.lightSleepMinutes,
                    awakeMin: matchingSleep?.awakeMinutes,
                    respiratoryRate: matchingSleep?.respiratoryRate
                )
                modelContext.insert(histDaily)
            }
            try? modelContext.save()
        }

        // Load historical data — always fetch 90 days so range switching is instant
        let historyDays = 90
        let historyStart = Calendar.current.date(
            byAdding: .day, value: -historyDays, to: today
        ) ?? today

        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date >= historyStart },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        recentRecoveries = (try? modelContext.fetch(descriptor)) ?? []

        // Detect trends
        insights = recoveryEngine.detectTrends(
            recoveries: recentRecoveries,
            days: historyDays
        )

        todayRecovery = recovery
        todayPrescription = prescription

        // Now that recentRecoveries is populated, inject anomaly warnings (Task 4)
        let anomalies = activeAnomalies
        if !anomalies.isEmpty {
            var currentWarnings = prescription.warnings
            for anomaly in anomalies {
                let warningText = "\(anomaly.title): \(anomaly.detail)"
                if !currentWarnings.contains(warningText) {
                    currentWarnings.append(warningText)
                }
            }
            prescription.warnings = currentWarnings
            try? modelContext.save()
        }

        // A failure only reads as an error when it leaves nothing to show.
        loadState = RecoveryLoadResolver.resolve(
            isConnectedToRealData: connectedToRealData,
            fetchedAnything: recoveryData != nil || sleepData != nil || cycleData != nil,
            todayHasReadings: Self.reading(from: recovery).hasReadings,
            saveFailed: saveFailed
        )
    }

    /// One-time 30-day historical backfill of recovery + sleep + cycle data,
    /// run on first successful WHOOP connect. Gated by
    /// `WhoopConnection.didBackfill`; idempotent (skips dates already stored)
    /// so a mid-backfill failure safely retries on next launch. The flag is
    /// only set after `modelContext.save()` succeeds.
    func backfillIfNeeded(modelContext: ModelContext) async {
        // Fetch-or-create the WhoopConnection row (nothing creates it elsewhere).
        var connDescriptor = FetchDescriptor<WhoopConnection>()
        connDescriptor.fetchLimit = 1
        let connection: WhoopConnection
        if let existing = try? modelContext.fetch(connDescriptor).first {
            connection = existing
        } else {
            connection = WhoopConnection(isConnected: true)
            modelContext.insert(connection)
        }

        guard !connection.didBackfill else {
            return
        }

        let cal = Calendar.current
        let today = Date()
        let todayStart = cal.startOfDay(for: today)
        guard let backfillStart = cal.date(byAdding: .day, value: -30, to: todayStart) else {
            return
        }

        let recoveryBatch = (try? await whoop.fetchRecoveryBatch(start: backfillStart, end: today)) ?? []
        let sleepBatch = (try? await whoop.fetchSleepBatch(start: backfillStart, end: today)) ?? []

        for histRecovery in recoveryBatch {
            let histDate = cal.startOfDay(for: histRecovery.date)
            guard histDate < todayStart else {
                continue // today is handled by the normal refresh path
            }

            let checkDescriptor = FetchDescriptor<DailyRecovery>(
                predicate: #Predicate { $0.date == histDate }
            )
            if (try? modelContext.fetchCount(checkDescriptor)) ?? 0 > 0 {
                continue
            }

            let matchingSleep = sleepBatch.first {
                cal.startOfDay(for: $0.date) == histDate
            }
            // Cycle data is per-date on the WHOOP API; one call per backfilled
            // day is acceptable for a one-time operation.
            let cycle = try? await whoop.fetchCycle(for: histDate)

            let histDaily = DailyRecovery(
                date: histDate,
                recoveryScore: histRecovery.score,
                hrvRmssd: histRecovery.hrvRmssd,
                restingHR: histRecovery.restingHeartRate,
                spo2: histRecovery.spo2,
                skinTemp: histRecovery.skinTemp,
                sleepHours: matchingSleep?.totalHours,
                sleepScore: matchingSleep?.sleepScore,
                sleepEfficiency: matchingSleep?.sleepEfficiency,
                sleepConsistency: matchingSleep?.sleepConsistency,
                deepSleepMin: matchingSleep?.deepSleepMinutes,
                remSleepMin: matchingSleep?.remSleepMinutes,
                lightSleepMin: matchingSleep?.lightSleepMinutes,
                awakeMin: matchingSleep?.awakeMinutes,
                respiratoryRate: matchingSleep?.respiratoryRate,
                strain: cycle?.strain,
                avgHR: cycle?.averageHeartRate,
                maxHR: cycle?.maxHeartRate,
                caloriesBurned: cycle?.caloriesBurned
            )
            modelContext.insert(histDaily)
        }

        do {
            try modelContext.save()
            connection.didBackfill = true
            try? modelContext.save()
        } catch {
            // Leave didBackfill false so the next launch retries; the
            // existence check above makes the retry safe.
        }
    }

    // MARK: - Trend Range

    enum TrendRange: String, CaseIterable {
        case week = "7D"
        case month = "30D"
        case quarter = "90D"
    }

    func trendRangeDays(_ range: TrendRange) -> Int {
        switch range {
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    // MARK: - Formatted Display Values

    // Per MODULE_RECOVERY.md Section 13 — Data Formatting Rules

    var formattedRecoveryScore: String {
        guard let score = todayRecovery?.recoveryScore else {
            return "--"
        }
        return "\(Int(score))"
    }

    var recoveryZone: RecoveryZone {
        guard let score = todayRecovery?.recoveryScore else {
            return .red
        }
        return RecoveryZone(score: score)
    }

    var formattedHRV: String {
        guard let hrv = todayRecovery?.hrvRmssd else {
            return "--"
        }
        return "\(Int(hrv))"
    }

    var formattedRHR: String {
        guard let rhr = todayRecovery?.restingHR else {
            return "--"
        }
        return "\(Int(rhr))"
    }

    var formattedSpO2: String {
        guard let spo2 = todayRecovery?.spo2 else {
            return "--"
        }
        return "\(Int(spo2))"
    }

    var formattedSkinTemp: String {
        guard let temp = todayRecovery?.skinTemp else {
            return "--"
        }
        return temp.tempoDecimal(1)
    }

    var formattedSleepHours: String {
        guard let hours = todayRecovery?.sleepHours else {
            return "--"
        }
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    var formattedSleepScore: String {
        guard let score = todayRecovery?.sleepScore else {
            return "--"
        }
        return "\(Int(score))%"
    }

    var formattedStrain: String {
        guard let strain = todayRecovery?.strain else {
            return "--"
        }
        return strain.tempoDecimal(1)
    }

    var formattedCalories: String {
        guard let cal = todayRecovery?.caloriesBurned else {
            return "--"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: cal)) ?? "\(Int(cal))"
    }

    var formattedBedtime: String {
        guard let bedtime = todayPrescription?.bedtimeTarget else {
            return "--"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = String(localized: "h:mm a", comment: "DATE_FORMAT")
        return formatter.string(from: bedtime)
    }

    var formattedCaffeineCutoff: String {
        todayPrescription?.caffeineCutoffFormatted ?? "--"
    }

    var formattedHydration: String {
        guard let ml = todayPrescription?.hydrationTargetMl else {
            return "--"
        }
        let liters = Double(ml) / 1000.0
        return "\(liters.tempoDecimal(1))L"
    }

    // MARK: - Sleep Need (Task 1)

    // Calculated sleep need: baseline + strain adjustment

    var formattedSleepNeeded: String {
        guard let baseline = todayRecovery?.sleepNeededBaseline else {
            return "--"
        }
        // Strain adjustment: +0.5h for moderate strain (10-14), +1h for high (14+)
        let strainAdjustment: Double = if let strain = todayRecovery?.strain {
            switch strain {
            case 14...: 1.0
            case 10 ..< 14: 0.5
            default: 0
            }
        } else {
            0
        }
        let totalNeeded = baseline + strainAdjustment
        let h = Int(totalNeeded)
        let m = Int((totalNeeded - Double(h)) * 60)
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    var sleepNeededHours: Double? {
        guard let baseline = todayRecovery?.sleepNeededBaseline else {
            return nil
        }
        let strainAdjustment: Double = if let strain = todayRecovery?.strain {
            switch strain {
            case 14...: 1.0
            case 10 ..< 14: 0.5
            default: 0
            }
        } else {
            0
        }
        return baseline + strainAdjustment
    }

    // MARK: - Recovery Score Breakdown (Task 2)

    // 30-day baselines for HRV, RHR, Sleep

    var hrvBaseline30d: Double? {
        let values = recentRecoveries.suffix(30).compactMap(\.hrvRmssd)
        guard values.count >= 2 else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    var rhrBaseline30d: Double? {
        let values = recentRecoveries.suffix(30).compactMap(\.restingHR)
        guard values.count >= 2 else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    var sleepBaseline30d: Double? {
        let values = recentRecoveries.suffix(30).compactMap(\.sleepHours)
        guard values.count >= 2 else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    /// HRV delta vs 30-day average. Positive = better (higher HRV is good).
    var hrvDelta: Double? {
        guard let today = todayRecovery?.hrvRmssd, let baseline = hrvBaseline30d else {
            return nil
        }
        return today - baseline
    }

    /// RHR delta vs 30-day average. Negative = better (lower RHR is good).
    var rhrDelta: Double? {
        guard let today = todayRecovery?.restingHR, let baseline = rhrBaseline30d else {
            return nil
        }
        return today - baseline
    }

    /// Sleep delta vs baseline need. Positive = got more than needed.
    var sleepDelta: Double? {
        guard let hours = todayRecovery?.sleepHours else {
            return nil
        }
        let baseline = sleepNeededHours ?? sleepBaseline30d ?? 8.0
        return hours - baseline
    }

    // MARK: - Metric Baseline Indicators (Task 3)

    // SpO2 and Skin Temp 30-day baselines

    var spo2Baseline30d: Double? {
        let values = recentRecoveries.suffix(30).compactMap(\.spo2)
        guard values.count >= 2 else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    var spo2Delta: Double? {
        guard let today = todayRecovery?.spo2, let baseline = spo2Baseline30d else {
            return nil
        }
        return today - baseline
    }

    var skinTempBaseline30d: Double? {
        let values = recentRecoveries.suffix(30).compactMap(\.skinTemp)
        guard values.count >= 2 else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    var skinTempDelta: Double? {
        guard let today = todayRecovery?.skinTemp, let baseline = skinTempBaseline30d else {
            return nil
        }
        return today - baseline
    }

    // MARK: - Chart Data

    /// Every stored day as plain readings (days without any reading left out).
    var readings: [RecoveryDayReading] {
        recentRecoveries.map(Self.reading(from:)).filter(\.hasReadings)
    }

    static func reading(from recovery: DailyRecovery) -> RecoveryDayReading {
        RecoveryDayReading(
            date: recovery.date,
            recovery: recovery.recoveryScore,
            hrv: recovery.hrvRmssd,
            rhr: recovery.restingHR,
            sleepHours: recovery.sleepHours,
            strain: recovery.strain
        )
    }

    /// The calendar days the selected range covers, oldest first.
    var periodReadings: [RecoveryDayReading] {
        RecoveryWindow.select(
            readings, days: trendRangeDays(selectedTrendRange), endingOn: Date()
        )
    }

    /// Averages, best and worst day and zone counts of the selected range, with
    /// the range before it for comparison. Nil under three days of readings.
    var periodStats: RecoveryPeriodStats? {
        let days = trendRangeDays(selectedTrendRange)
        return RecoveryPeriodStats.make(
            window: periodReadings,
            previous: RecoveryWindow.previous(readings, days: days, endingOn: Date())
        )
    }

    /// Days with readings in the last `days` calendar days, as stored rows.
    func recoveries(lastDays days: Int) -> [DailyRecovery] {
        let window = Set(
            RecoveryWindow.select(readings, days: days, endingOn: Date()).map(\.date)
        )
        return recentRecoveries.filter { window.contains($0.date) }
    }

    var recoveryChartData: [(Date, Double)] {
        periodReadings.map { ($0.date, $0.recovery) }
    }

    var hrvChartData: [(Date, Double)] {
        periodReadings.compactMap { r in r.hrv.map { (r.date, $0) } }
    }

    var rhrChartData: [(Date, Double)] {
        periodReadings.compactMap { r in r.rhr.map { (r.date, $0) } }
    }

    var sleepChartData: [(Date, Double)] {
        periodReadings.compactMap { r in r.sleepHours.map { (r.date, $0) } }
    }

    var strainChartData: [(Date, Double)] {
        periodReadings.compactMap { r in r.strain.map { (r.date, $0) } }
    }

    // MARK: - Recovery Comparison

    // Per MODULE_RECOVERY.md Section 4.2 — Comparison label

    var comparisonText: String {
        guard let score = todayRecovery?.recoveryScore,
              let avg = avg30dRecovery
        else {
            return String(localized: "Your first recovery day!")
        }
        let diff = score - avg
        let percent = abs(diff / avg * 100)
        if abs(diff) < 1 {
            return String(localized: "Right at your average")
        } else if diff > 0 {
            return String(localized: "↑ \(Int(percent))% above your average")
        } else {
            return String(localized: "↓ \(Int(percent))% below your average")
        }
    }

    var comparisonIsPositive: Bool {
        guard let score = todayRecovery?.recoveryScore,
              let avg = avg30dRecovery
        else {
            return true
        }
        return score >= avg
    }

    private var avg30dRecovery: Double? {
        let values = recentRecoveries.suffix(30).map(\.recoveryScore)
        guard values.count >= 2 else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Recovery Score Explanation (Task 1)

    // Generates contextual text explaining WHY the recovery score is what it is

    var recoveryExplanation: String {
        guard let recovery = todayRecovery else {
            return String(localized: "Waiting for recovery data to generate insights.")
        }

        let zone = RecoveryZone(score: recovery.recoveryScore)
        var factors: [String] = []

        // HRV factor
        if let hrvDelta, let baseline = hrvBaseline30d {
            let absD = abs(Int(hrvDelta))
            if hrvDelta < -5 {
                factors.append(String(localized: "Your HRV dropped \(absD)ms below your \(Int(baseline))ms baseline"))
            } else if hrvDelta > 5 {
                factors.append(String(localized: "Your HRV is \(absD)ms above your \(Int(baseline))ms baseline"))
            } else {
                factors.append(String(localized: "Your HRV is right at your \(Int(baseline))ms baseline"))
            }
        }

        // RHR factor
        if let rhrDelta, let baseline = rhrBaseline30d {
            let absD = abs(Int(rhrDelta))
            if rhrDelta > 3 {
                factors.append(String(localized: "your RHR is elevated \(absD)bpm above your \(Int(baseline))bpm average"))
            } else if rhrDelta < -3 {
                factors.append(String(localized: "your RHR is \(absD)bpm below your \(Int(baseline))bpm average (good sign)"))
            }
        }

        // Sleep factor
        if let sleepHours = recovery.sleepHours {
            let needed = sleepNeededHours ?? 8.0
            if sleepHours >= needed {
                let extra = sleepHours - needed
                factors
                    .append(
                        String(localized: "you got \(sleepHours.tempoDecimal(1))h of sleep (+\(extra.tempoDecimal(1))h vs your \(needed.tempoDecimal(1))h target)")
                    )
            } else {
                let deficit = needed - sleepHours
                factors
                    .append(
                        String(localized: "you only got \(sleepHours.tempoDecimal(1))h of sleep (\(deficit.tempoDecimal(1))h short of your \(needed.tempoDecimal(1))h target)")
                    )
            }
        }

        // Strain context from yesterday
        if let strain = recovery.strain, strain > 14 {
            factors.append(String(localized: "your body is still recovering from yesterday's high strain (\(strain.tempoDecimal(1)))"))
        }

        // SpO2 warning
        if let spo2 = recovery.spo2, spo2 < 95 {
            factors.append(String(localized: "your SpO2 is low at \(Int(spo2))%"))
        }

        // Skin temp warning
        if let skinDelta = skinTempDelta, abs(skinDelta) > 0.5 {
            factors
                .append(
                    skinDelta > 0
                        ? String(localized: "your skin temperature is \(abs(skinDelta).tempoDecimal(1))°C above baseline")
                        : String(localized: "your skin temperature is \(abs(skinDelta).tempoDecimal(1))°C below baseline")
                )
        }

        // Sleep debt
        if let debt = recovery.sleepDebt, debt > 2 {
            factors.append(String(localized: "you're carrying \(debt.tempoDecimal(1))h of sleep debt"))
        }

        // Build the explanation sentence
        guard !factors.isEmpty else {
            switch zone {
            case .green: return String(localized: "Good recovery. Your biometrics are within normal range.")
            case .yellow: return String(localized: "Moderate recovery. Monitor your metrics and adjust training accordingly.")
            case .red: return String(localized: "Low recovery. Prioritize rest and sleep today.")
            }
        }

        let prefix = switch zone {
        case .green:
            String(localized: "Excellent recovery.")
        case .yellow:
            String(localized: "Moderate recovery.")
        case .red:
            String(localized: "Your body needs recovery.")
        }

        // Capitalize first factor, join the rest with commas
        var joined = factors[0]
        if factors.count > 1 {
            joined += ", " + factors[1 ..< factors.count].joined(separator: ", ")
        }
        // Capitalize the first letter
        let capitalizedJoined = joined.prefix(1).uppercased() + joined.dropFirst()

        return "\(prefix) \(capitalizedJoined)."
    }

    // MARK: - Anomaly Detection & Warnings (Task 4)

    // Real-time anomaly detection based on 7-day averages

    struct AnomalyWarning: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let severity: AnomalySeverity
    }

    enum AnomalySeverity {
        case warning // yellow
        case critical // red
    }

    var activeAnomalies: [AnomalyWarning] {
        guard let recovery = todayRecovery else {
            return []
        }
        var anomalies: [AnomalyWarning] = []

        // HRV drops >20% below 7-day average
        if let todayHRV = recovery.hrvRmssd, let avg7d = hrvAvg7d, avg7d > 0 {
            let dropPercent = (avg7d - todayHRV) / avg7d * 100
            if dropPercent > 20 {
                anomalies.append(AnomalyWarning(
                    icon: "waveform.path.ecg",
                    title: String(localized: "HRV Significantly Below Average"),
                    detail: String(localized: "Your HRV (\(Int(todayHRV))ms) is \(Int(dropPercent))% below your 7-day average (\(Int(avg7d))ms). This may indicate stress, illness, or overtraining."),
                    severity: dropPercent > 30 ? .critical : .warning
                ))
            }
        }

        // RHR increases >10% above 7-day average
        if let todayRHR = recovery.restingHR, let avg7d = rhrAvg7d, avg7d > 0 {
            let risePercent = (todayRHR - avg7d) / avg7d * 100
            if risePercent > 10 {
                anomalies.append(AnomalyWarning(
                    icon: "heart.fill",
                    title: String(localized: "Resting Heart Rate Elevated"),
                    detail: String(localized: "Your RHR (\(Int(todayRHR))bpm) is \(Int(risePercent))% above your 7-day average (\(Int(avg7d))bpm). Elevated RHR can signal stress, dehydration, or oncoming illness."),
                    severity: risePercent > 20 ? .critical : .warning
                ))
            }
        }

        // SpO2 drops below 95%
        if let spo2 = recovery.spo2, spo2 < 95 {
            anomalies.append(AnomalyWarning(
                icon: "lungs.fill",
                title: String(localized: "Low Blood Oxygen"),
                detail: String(localized: "Your SpO2 (\(Int(spo2))%) is below the normal range (95-100%). If this persists, consult a healthcare professional."),
                severity: spo2 < 92 ? .critical : .warning
            ))
        }

        // Skin temp increases >0.5C above baseline
        if let skinDelta = skinTempDelta, skinDelta > 0.5 {
            anomalies.append(AnomalyWarning(
                icon: "thermometer.high",
                title: String(localized: "Elevated Skin Temperature"),
                detail: String(localized: "Your skin temperature is +\(skinDelta.tempoDecimal(1))°C above your baseline. This may indicate inflammation, fever, or oncoming illness."),
                severity: skinDelta > 1.0 ? .critical : .warning
            ))
        }

        return anomalies
    }

    /// 7-day HRV average (distinct from 30-day baseline, used for anomaly detection)
    private var hrvAvg7d: Double? {
        let values = recentRecoveries.suffix(7).compactMap(\.hrvRmssd)
        guard values.count >= 3 else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 7-day RHR average (distinct from 30-day baseline, used for anomaly detection)
    private var rhrAvg7d: Double? {
        let values = recentRecoveries.suffix(7).compactMap(\.restingHR)
        guard values.count >= 3 else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Sleep Debt Tracking (Task 3)

    // Calculate accumulated sleep debt over past 7 days

    var calculatedSleepDebt: Double {
        let last7 = Array(recentRecoveries.suffix(7))
        guard !last7.isEmpty else {
            return 0
        }

        let sleepNeed = todayRecovery?.sleepNeededBaseline ?? 8.0
        var totalDebt: Double = 0

        for recovery in last7 {
            if let hours = recovery.sleepHours {
                let deficit = max(0, sleepNeed - hours)
                totalDebt += deficit
            }
        }
        return totalDebt
    }

    var sleepDebtSeverity: SleepDebtSeverity {
        let debt = calculatedSleepDebt
        if debt < 2 {
            return .minimal
        }
        if debt < 5 {
            return .moderate
        }
        if debt < 8 {
            return .significant
        }
        return .critical
    }

    enum SleepDebtSeverity: String {
        case minimal = "Minimal"
        case moderate = "Moderate"
        case significant = "Significant"
        case critical = "Critical"

        /// The word shown on screen. `rawValue` stays the stable English value.
        var title: String {
            switch self {
            case .minimal: String(localized: "Minimal")
            case .moderate: String(localized: "Moderate")
            case .significant: String(localized: "Significant")
            case .critical: String(localized: "Critical")
            }
        }
    }

    var sleepDebtPaybackPlan: String? {
        let debt = calculatedSleepDebt
        guard debt >= 1.0 else {
            return nil
        }

        // Recommend spreading payback over 3 nights (max 1h extra per night)
        let nightsNeeded = Int(ceil(debt))
        let extraPerNight = min(debt / Double(min(nightsNeeded, 3)), 1.0)

        if debt < 2 {
            return String(localized: "Add \(Int(extraPerNight * 60)) extra minutes tonight to recover your \(debt.tempoDecimal(1))h deficit.")
        } else if debt < 5 {
            return String(localized: "You need about \((extraPerNight * 60).tempoDecimal(0)) extra minutes each night over the next \(min(nightsNeeded, 3)) nights to recover your \(debt.tempoDecimal(1))h deficit.")
        } else {
            return String(localized: "Significant debt of \(debt.tempoDecimal(1))h. Aim for 1 extra hour per night for the next \(min(nightsNeeded, 7)) nights. Prioritize early bedtimes and sleep hygiene.")
        }
    }

    // MARK: - Bedtime Recommendation Enhancement (Task 6)

    // Smart bedtime calculation with sleep debt factoring

    var smartBedtimeExplanation: String? {
        guard let bedtime = todayPrescription?.bedtimeTarget else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = String(localized: "h:mm a", comment: "DATE_FORMAT")
        let bedtimeStr = formatter.string(from: bedtime)

        let sleepNeeded = sleepNeededHours ?? 8.0
        let h = Int(sleepNeeded)
        let m = Int((sleepNeeded - Double(h)) * 60)
        let sleepStr = m > 0 ? "\(h)h \(m)m" : "\(h)h"

        var explanation = String(localized: "Get to bed by \(bedtimeStr) to hit your \(sleepStr) target")

        // Explain components
        var components: [String] = []

        // Base need
        let baseline = todayRecovery?.sleepNeededBaseline ?? 8.0
        components.append(String(localized: "\(baseline.tempoDecimal(1))h base need"))

        // Strain adjustment
        if let strain = todayRecovery?.strain, strain >= 10 {
            let adj = strain >= 14 ? "1h" : "30m"
            components.append(String(localized: "+\(adj) for yesterday's strain"))
        }

        // Sleep debt adjustment
        let debt = calculatedSleepDebt
        if debt > 2 {
            components.append(String(localized: "+30m to pay down \(debt.tempoDecimal(1))h sleep debt"))
        }

        // Fall-asleep buffer
        components.append(String(localized: "15m fall-asleep buffer"))

        explanation += " (\(components.joined(separator: ", ")))."

        return explanation
    }

    // MARK: - Sleep Stage Data

    var deepSleepMinutes: Int {
        todayRecovery?.deepSleepMin ?? 0
    }

    var remSleepMinutes: Int {
        todayRecovery?.remSleepMin ?? 0
    }

    var lightSleepMinutes: Int {
        todayRecovery?.lightSleepMin ?? 0
    }

    var awakeMinutes: Int {
        todayRecovery?.awakeMin ?? 0
    }

    var totalSleepStageMinutes: Int {
        deepSleepMinutes + remSleepMinutes + lightSleepMinutes
    }

    // MARK: - Private Helpers

    private func buildDailyRecovery(
        date: Date,
        recoveryData: WhoopRecoveryData?,
        sleepData: WhoopSleepData?,
        cycleData: WhoopCycleData?,
        modelContext: ModelContext
    ) -> DailyRecovery {
        let startOfDay = Calendar.current.startOfDay(for: date)

        // Check if we already have a recovery for today
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date == startOfDay }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            // Update existing record with fresh data
            if let r = recoveryData {
                existing.recoveryScore = r.score
                existing.hrvRmssd = r.hrvRmssd
                existing.restingHR = r.restingHeartRate
                existing.spo2 = r.spo2
                existing.skinTemp = r.skinTemp
                existing.recoveryZoneRaw = RecoveryZone(score: r.score).rawValue
            }
            if let s = sleepData {
                existing.sleepHours = s.totalHours
                existing.sleepScore = s.sleepScore
                existing.sleepEfficiency = s.sleepEfficiency
                existing.sleepConsistency = s.sleepConsistency
                existing.deepSleepMin = s.deepSleepMinutes
                existing.remSleepMin = s.remSleepMinutes
                existing.lightSleepMin = s.lightSleepMinutes
                existing.awakeMin = s.awakeMinutes
                existing.respiratoryRate = s.respiratoryRate
            }
            if let c = cycleData {
                existing.strain = c.strain
                existing.avgHR = c.averageHeartRate
                existing.maxHR = c.maxHeartRate
                existing.caloriesBurned = c.caloriesBurned
            }
            return existing
        }

        // Create new
        return DailyRecovery(
            date: date,
            recoveryScore: recoveryData?.score ?? 0,
            hrvRmssd: recoveryData?.hrvRmssd,
            restingHR: recoveryData?.restingHeartRate,
            spo2: recoveryData?.spo2,
            skinTemp: recoveryData?.skinTemp,
            sleepHours: sleepData?.totalHours,
            sleepScore: sleepData?.sleepScore,
            sleepEfficiency: sleepData?.sleepEfficiency,
            sleepConsistency: sleepData?.sleepConsistency,
            deepSleepMin: sleepData?.deepSleepMinutes,
            remSleepMin: sleepData?.remSleepMinutes,
            lightSleepMin: sleepData?.lightSleepMinutes,
            awakeMin: sleepData?.awakeMinutes,
            respiratoryRate: sleepData?.respiratoryRate,
            strain: cycleData?.strain,
            avgHR: cycleData?.averageHeartRate,
            maxHR: cycleData?.maxHeartRate,
            caloriesBurned: cycleData?.caloriesBurned
        )
    }
}
