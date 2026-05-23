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

enum RecoveryLoadState {
    case loading
    case loaded
    case error(String)
}

// MARK: - RecoveryTab

enum RecoveryTab: String, CaseIterable {
    case today = "Today"
    case sleep = "Sleep"
    case strain = "Strain"
    case trends = "Trends"
}

// MARK: - RecoveryViewModel

// Per MODULE_RECOVERY.md Sections 4-7 and BUILD_PLAN.md Step 8.2.

@Observable
@MainActor
final class RecoveryViewModel {
    // MARK: - State

    var loadState: RecoveryLoadState = .loading
    var selectedTab: RecoveryTab = .today
    var selectedTrendRange: TrendRange = .week

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
    func forceRefresh(modelContext: ModelContext) async {
        await whoop.invalidateCache()
        await refresh(modelContext: modelContext)
    }

    func refresh(modelContext: ModelContext) async {
        loadState = .loading

        let today = Date()

        // Fetch Whoop data only when connected (skip if backend unreachable)
        let recoveryData: WhoopRecoveryData?
        let sleepData: WhoopSleepData?
        let cycleData: WhoopCycleData?
        if whoop.connectionState == .connected {
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

        // Insert prescription, then link relationship
        modelContext.insert(prescription)
        prescription.dailyRecovery = recovery

        // Inject anomaly-based warnings into prescription (Task 4)
        // We need recentRecoveries loaded first for 7-day averages,
        // so we'll add anomaly warnings after the full data load below.

        try? modelContext.save()

        // Seed historical records from Whoop batch data (fills trends on first launch).
        // Only creates new records for dates that don't already exist in the database.
        if whoop.connectionState == .connected {
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

        loadState = .loaded
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
        return String(format: "%.1f", temp)
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
        return String(format: "%.1f", strain)
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
        formatter.dateFormat = "h:mm a"
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
        return String(format: "%.1fL", liters)
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

    // MARK: - Calorie Split (Task 4)

    // Estimate active vs basal calories from strain

    /// Active calories estimated from strain (Whoop strain correlates with active energy).
    /// Uses the Whoop strain-to-calorie relationship: higher strain = more active burn.
    var activeCalories: Double? {
        guard let totalCal = todayRecovery?.caloriesBurned,
              let strain = todayRecovery?.strain,
              totalCal > 0
        else {
            return nil
        }
        // Strain 0-21 scale. Basal metabolic rate is roughly 1600-2000 kcal/day.
        // Active calories = total - estimated basal.
        // Estimate basal as total minus strain-proportional active component.
        // Whoop strain is logarithmic; approximate active fraction from strain level.
        let strainFraction = min(strain / 21.0, 1.0)
        // At strain 0, ~100% basal. At strain 21, ~60% active.
        let activeFraction = strainFraction * 0.6
        let active = totalCal * activeFraction
        return max(active, 0)
    }

    var basalCalories: Double? {
        guard let totalCal = todayRecovery?.caloriesBurned,
              let active = activeCalories
        else {
            return nil
        }
        return totalCal - active
    }

    var activeCaloriePercent: Int? {
        guard let totalCal = todayRecovery?.caloriesBurned,
              let active = activeCalories,
              totalCal > 0
        else {
            return nil
        }
        return Int((active / totalCal) * 100)
    }

    var basalCaloriePercent: Int? {
        guard let active = activeCaloriePercent else {
            return nil
        }
        return 100 - active
    }

    // MARK: - Chart Data

    /// Recoveries filtered to the selected trend range (7/30/90 days)
    private var rangeFilteredRecoveries: [DailyRecovery] {
        let days = trendRangeDays(selectedTrendRange)
        return Array(recentRecoveries.suffix(days))
    }

    var recoveryChartData: [(Date, Double)] {
        rangeFilteredRecoveries.map { ($0.date, $0.recoveryScore) }
    }

    var hrvChartData: [(Date, Double)] {
        rangeFilteredRecoveries.compactMap { r in
            guard let hrv = r.hrvRmssd else {
                return nil
            }
            return (r.date, hrv)
        }
    }

    var rhrChartData: [(Date, Double)] {
        rangeFilteredRecoveries.compactMap { r in
            guard let rhr = r.restingHR else {
                return nil
            }
            return (r.date, rhr)
        }
    }

    var sleepChartData: [(Date, Double)] {
        rangeFilteredRecoveries.compactMap { r in
            guard let hours = r.sleepHours else {
                return nil
            }
            return (r.date, hours)
        }
    }

    var strainChartData: [(Date, Double)] {
        rangeFilteredRecoveries.compactMap { r in
            guard let strain = r.strain else {
                return nil
            }
            return (r.date, strain)
        }
    }

    // MARK: - Averages (dynamic based on selectedTrendRange)

    var avgRecovery7d: Double? {
        let recent = rangeFilteredRecoveries
        guard !recent.isEmpty else {
            return nil
        }
        return recent.map(\.recoveryScore).reduce(0, +) / Double(recent.count)
    }

    var avgHRV7d: Double? {
        let values = rangeFilteredRecoveries.compactMap(\.hrvRmssd)
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    var avgRHR7d: Double? {
        let values = rangeFilteredRecoveries.compactMap(\.restingHR)
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Recovery Comparison

    // Per MODULE_RECOVERY.md Section 4.2 — Comparison label

    var comparisonText: String {
        guard let score = todayRecovery?.recoveryScore,
              let avg = avg30dRecovery
        else {
            return "Your first recovery day!"
        }
        let diff = score - avg
        let percent = abs(diff / avg * 100)
        if abs(diff) < 1 {
            return "Right at your average"
        } else if diff > 0 {
            return "↑ \(Int(percent))% above your average"
        } else {
            return "↓ \(Int(percent))% below your average"
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
            return "Waiting for recovery data to generate insights."
        }

        let zone = RecoveryZone(score: recovery.recoveryScore)
        var factors: [String] = []

        // HRV factor
        if let hrvDelta, let baseline = hrvBaseline30d {
            let absD = abs(Int(hrvDelta))
            if hrvDelta < -5 {
                factors.append("Your HRV dropped \(absD)ms below your \(Int(baseline))ms baseline")
            } else if hrvDelta > 5 {
                factors.append("Your HRV is \(absD)ms above your \(Int(baseline))ms baseline")
            } else {
                factors.append("Your HRV is right at your \(Int(baseline))ms baseline")
            }
        }

        // RHR factor
        if let rhrDelta, let baseline = rhrBaseline30d {
            let absD = abs(Int(rhrDelta))
            if rhrDelta > 3 {
                factors.append("your RHR is elevated \(absD)bpm above your \(Int(baseline))bpm average")
            } else if rhrDelta < -3 {
                factors.append("your RHR is \(absD)bpm below your \(Int(baseline))bpm average (good sign)")
            }
        }

        // Sleep factor
        if let sleepHours = recovery.sleepHours {
            let needed = sleepNeededHours ?? 8.0
            if sleepHours >= needed {
                let extra = sleepHours - needed
                factors
                    .append(
                        "you got \(String(format: "%.1f", sleepHours))h of sleep (\(String(format: "+%.1f", extra))h vs your \(String(format: "%.1f", needed))h target)"
                    )
            } else {
                let deficit = needed - sleepHours
                factors
                    .append(
                        "you only got \(String(format: "%.1f", sleepHours))h of sleep (\(String(format: "%.1f", deficit))h short of your \(String(format: "%.1f", needed))h target)"
                    )
            }
        }

        // Strain context from yesterday
        if let strain = recovery.strain, strain > 14 {
            factors.append("your body is still recovering from yesterday's high strain (\(String(format: "%.1f", strain)))")
        }

        // SpO2 warning
        if let spo2 = recovery.spo2, spo2 < 95 {
            factors.append("your SpO2 is low at \(Int(spo2))%")
        }

        // Skin temp warning
        if let skinDelta = skinTempDelta, abs(skinDelta) > 0.5 {
            factors
                .append(
                    "your skin temperature is \(String(format: "%.1f", abs(skinDelta)))°C \(skinDelta > 0 ? "above" : "below") baseline"
                )
        }

        // Sleep debt
        if let debt = recovery.sleepDebt, debt > 2 {
            factors.append("you're carrying \(String(format: "%.1f", debt))h of sleep debt")
        }

        // Build the explanation sentence
        guard !factors.isEmpty else {
            switch zone {
            case .green: return "Good recovery. Your biometrics are within normal range."
            case .yellow: return "Moderate recovery. Monitor your metrics and adjust training accordingly."
            case .red: return "Low recovery. Prioritize rest and sleep today."
            }
        }

        let prefix = switch zone {
        case .green:
            "Excellent recovery."
        case .yellow:
            "Moderate recovery."
        case .red:
            "Your body needs recovery."
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
                    title: "HRV Significantly Below Average",
                    detail: "Your HRV (\(Int(todayHRV))ms) is \(Int(dropPercent))% below your 7-day average (\(Int(avg7d))ms). This may indicate stress, illness, or overtraining.",
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
                    title: "Resting Heart Rate Elevated",
                    detail: "Your RHR (\(Int(todayRHR))bpm) is \(Int(risePercent))% above your 7-day average (\(Int(avg7d))bpm). Elevated RHR can signal stress, dehydration, or oncoming illness.",
                    severity: risePercent > 20 ? .critical : .warning
                ))
            }
        }

        // SpO2 drops below 95%
        if let spo2 = recovery.spo2, spo2 < 95 {
            anomalies.append(AnomalyWarning(
                icon: "lungs.fill",
                title: "Low Blood Oxygen",
                detail: "Your SpO2 (\(Int(spo2))%) is below the normal range (95-100%). If this persists, consult a healthcare professional.",
                severity: spo2 < 92 ? .critical : .warning
            ))
        }

        // Skin temp increases >0.5C above baseline
        if let skinDelta = skinTempDelta, skinDelta > 0.5 {
            anomalies.append(AnomalyWarning(
                icon: "thermometer.high",
                title: "Elevated Skin Temperature",
                detail: "Your skin temperature is \(String(format: "+%.1f", skinDelta))°C above your baseline. This may indicate inflammation, fever, or oncoming illness.",
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
            return "Add \(Int(extraPerNight * 60)) extra minutes tonight to recover your \(String(format: "%.1f", debt))h deficit."
        } else if debt < 5 {
            return "You need about \(String(format: "%.0f", extraPerNight * 60)) extra minutes each night over the next \(min(nightsNeeded, 3)) nights to recover your \(String(format: "%.1f", debt))h deficit."
        } else {
            return "Significant debt of \(String(format: "%.1f", debt))h. Aim for 1 extra hour per night for the next \(min(nightsNeeded, 7)) nights. Prioritize early bedtimes and sleep hygiene."
        }
    }

    // MARK: - Bedtime Recommendation Enhancement (Task 6)

    // Smart bedtime calculation with sleep debt factoring

    var smartBedtimeExplanation: String? {
        guard let bedtime = todayPrescription?.bedtimeTarget else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let bedtimeStr = formatter.string(from: bedtime)

        let sleepNeeded = sleepNeededHours ?? 8.0
        let h = Int(sleepNeeded)
        let m = Int((sleepNeeded - Double(h)) * 60)
        let sleepStr = m > 0 ? "\(h)h \(m)m" : "\(h)h"

        var explanation = "Get to bed by \(bedtimeStr) to hit your \(sleepStr) target"

        // Explain components
        var components: [String] = []

        // Base need
        let baseline = todayRecovery?.sleepNeededBaseline ?? 8.0
        components.append("\(String(format: "%.1f", baseline))h base need")

        // Strain adjustment
        if let strain = todayRecovery?.strain, strain >= 10 {
            let adj = strain >= 14 ? "1h" : "30m"
            components.append("+\(adj) for yesterday's strain")
        }

        // Sleep debt adjustment
        let debt = calculatedSleepDebt
        if debt > 2 {
            components.append("+30m to pay down \(String(format: "%.1f", debt))h sleep debt")
        }

        // Fall-asleep buffer
        components.append("15m fall-asleep buffer")

        explanation += " (\(components.joined(separator: ", ")))."

        return explanation
    }

    // MARK: - Weekly Recovery Summary Data (Task 5)

    struct WeeklyStats {
        let avgRecovery: Double
        let avgHRV: Double
        let avgRHR: Double
        let avgSleep: Double
        let bestDay: (Date, Double)?
        let worstDay: (Date, Double)?
        let totalStrain: Double
        let prevWeekAvgRecovery: Double?
        let prevWeekAvgHRV: Double?
        let prevWeekAvgRHR: Double?
        let prevWeekAvgSleep: Double?
    }

    var weeklyStats: WeeklyStats? {
        let last7 = Array(recentRecoveries.suffix(7))
        guard last7.count >= 3 else {
            return nil
        }

        let recoveryScores = last7.map(\.recoveryScore)
        let hrvValues = last7.compactMap(\.hrvRmssd)
        let rhrValues = last7.compactMap(\.restingHR)
        let sleepValues = last7.compactMap(\.sleepHours)
        let strainValues = last7.compactMap(\.strain)

        let avgRecovery = recoveryScores.reduce(0, +) / Double(recoveryScores.count)
        let avgHRV = hrvValues.isEmpty ? 0 : hrvValues.reduce(0, +) / Double(hrvValues.count)
        let avgRHR = rhrValues.isEmpty ? 0 : rhrValues.reduce(0, +) / Double(rhrValues.count)
        let avgSleep = sleepValues.isEmpty ? 0 : sleepValues.reduce(0, +) / Double(sleepValues.count)
        let totalStrain = strainValues.reduce(0, +)

        let bestDay = last7.max(by: { $0.recoveryScore < $1.recoveryScore }).map { ($0.date, $0.recoveryScore) }
        let worstDay = last7.min(by: { $0.recoveryScore < $1.recoveryScore }).map { ($0.date, $0.recoveryScore) }

        // Previous week stats for comparison
        let prev14 = Array(recentRecoveries.suffix(14))
        let prevWeek = prev14.count > 7 ? Array(prev14.prefix(prev14.count - 7).suffix(7)) : []

        let prevAvgRecovery: Double? = prevWeek.count >= 3 ? prevWeek.map(\.recoveryScore).reduce(0, +) / Double(prevWeek.count) : nil
        let prevHRV = prevWeek.compactMap(\.hrvRmssd)
        let prevAvgHRV: Double? = prevHRV.count >= 3 ? prevHRV.reduce(0, +) / Double(prevHRV.count) : nil
        let prevRHR = prevWeek.compactMap(\.restingHR)
        let prevAvgRHR: Double? = prevRHR.count >= 3 ? prevRHR.reduce(0, +) / Double(prevRHR.count) : nil
        let prevSleep = prevWeek.compactMap(\.sleepHours)
        let prevAvgSleep: Double? = prevSleep.count >= 3 ? prevSleep.reduce(0, +) / Double(prevSleep.count) : nil

        return WeeklyStats(
            avgRecovery: avgRecovery,
            avgHRV: avgHRV,
            avgRHR: avgRHR,
            avgSleep: avgSleep,
            bestDay: bestDay,
            worstDay: worstDay,
            totalStrain: totalStrain,
            prevWeekAvgRecovery: prevAvgRecovery,
            prevWeekAvgHRV: prevAvgHRV,
            prevWeekAvgRHR: prevAvgRHR,
            prevWeekAvgSleep: prevAvgSleep
        )
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
