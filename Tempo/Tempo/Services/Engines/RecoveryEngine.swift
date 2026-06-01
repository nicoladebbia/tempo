//
// RecoveryEngine.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import os

// MARK: - Recovery Engine (Real Implementation)

// Per MODULE_RECOVERY.md Section 8 — Prescription Engine.
// Per EXERCISE_SCIENCE.md Sections 3, 5-7 — Scientific basis.
// Per STATE_MACHINES.md Section 13 — Prescription state machine.

final class RecoveryEngine: RecoveryEngineProtocol, @unchecked Sendable {
    private let logger = Logger(subsystem: "app.tempo", category: "RecoveryEngine")

    // MARK: - Generate Prescription

    // Per MODULE_RECOVERY.md Section 8.1–8.5

    func generatePrescription(
        recovery: DailyRecovery,
        schedule: [CalendarEvent]
    ) -> DailyPrescription {
        let score = recovery.recoveryScore
        let sleepDebt = recovery.sleepDebt ?? 0
        let sleepHours = recovery.sleepHours ?? 7.5
        let sleepEfficiency = recovery.sleepEfficiency ?? 85
        let strain = recovery.strain ?? 0

        // --- Training Prescription ---
        // Per MODULE_RECOVERY.md Section 8.2
        let training = generateTrainingPrescription(
            recoveryScore: Int(score),
            sleepHours: sleepHours,
            sleepEfficiency: sleepEfficiency,
            sleepDebt: sleepDebt,
            yesterdayStrain: strain,
            schedule: schedule
        )

        // --- Nutrition Recommendations ---
        // Per MODULE_RECOVERY.md Section 8.3
        var nutritionRecs: [String] = []

        // Rule 2: Low recovery — protein emphasis
        if score < 50 {
            nutritionRecs.append("Prioritize protein today — your recovery is low and muscles need repair.")
        }

        // Rule 3: Poor sleep — magnesium-rich foods
        if (recovery.sleepScore ?? 100) < 70 || sleepHours < 6.0 {
            nutritionRecs.append("Include magnesium-rich foods: dark leafy greens, almonds, pumpkin seeds.")
        }

        // Rule 1: High expected strain
        if hasPlannedTraining(schedule) {
            nutritionRecs.append("Eat carbs 1-2h before training. Aim for 30-50g carbs and 15-20g protein.")
        }

        // Rule 6: Football day
        if hasFootballToday(schedule) {
            nutritionRecs.insert("High-carb meal 3-4h before kickoff. Include rice, pasta, or bread with lean protein.", at: 0)
        }

        if nutritionRecs.isEmpty {
            nutritionRecs.append("Eat balanced meals today. Focus on whole foods and adequate protein.")
        }

        // --- Sleep Prescription ---
        // Per MODULE_RECOVERY.md Section 8.4
        let sleepRx = generateSleepPrescription(
            sleepDebt: sleepDebt,
            yesterdayStrain: strain,
            wakeTimeMinutes: 420 // Default 7:00 AM; will use UserSettings when available
        )

        // --- Hydration ---
        // Per MODULE_RECOVERY.md Section 8.5
        let hydrationMl = generateHydrationTarget(
            recoveryScore: score,
            plannedTraining: hasPlannedTraining(schedule),
            bodyWeightKg: 80 // Default; will use UserProfile when available
        )

        // --- Warnings ---
        // Per BUILD_PLAN.md acceptance criteria
        var warnings: [String] = []

        // Warning: Sleep debt > 4h
        if sleepDebt > 4.0 {
            warnings.append("Significant sleep debt (\(String(format: "%.1f", sleepDebt))h). Prioritize early bedtime tonight.")
        }

        // Warning: High strain with poor recovery
        if strain > 18, score < 67 {
            warnings
                .append("Yesterday's strain was very high (\(String(format: "%.1f", strain))) with below-average recovery. Take it easy.")
        }

        // Warning: Very low recovery
        if score < 34 {
            warnings
                .append(
                    "Recovery is in the red zone. If you experience persistent low recovery for 7+ days, consider consulting a healthcare professional."
                )
        }

        logger.info("Generated prescription: zone=\(training.zone), hydration=\(hydrationMl)ml, warnings=\(warnings.count)")

        // NOTE: Do NOT set dailyRecovery here — the caller sets the
        // relationship after both objects are in the SwiftData context
        // to avoid inverse-relationship assertion failures.
        return DailyPrescription(
            date: recovery.date,
            trainingRec: training.headline,
            trainingDetail: training.body,
            nutritionRecs: nutritionRecs,
            bedtimeTarget: sleepRx.bedtime,
            caffeineCutoff: sleepRx.caffeineCutoff,
            hydrationTargetMl: hydrationMl,
            warnings: warnings
        )
    }

    // MARK: - Classify Zone

    // Per MODULE_RECOVERY.md Section 8.2, CROSS_DOC_AUDIT.md Section 4

    func classifyZone(score: Double) -> RecoveryZone {
        RecoveryZone(score: score)
    }

    // MARK: - Calculate Sleep Debt

    // Per MODULE_RECOVERY.md Section 8.4

    func calculateSleepDebt(
        recentSleep: [Double],
        target: Double
    ) -> Double {
        guard !recentSleep.isEmpty else {
            return 0
        }

        // Rolling 7-day deficit accumulation
        // Per EXERCISE_SCIENCE.md: sleep debt accumulates linearly (Banks & Dinges, 2007)
        let daysToConsider = min(recentSleep.count, 7)
        let recentDays = recentSleep.suffix(daysToConsider)

        var totalDebt: Double = 0
        for hours in recentDays {
            let deficit = max(0, target - hours)
            totalDebt += deficit
        }

        return totalDebt
    }

    // MARK: - Detect Trends

    // Per MODULE_RECOVERY.md Section 7 (Trends View) and BUILD_PLAN.md 8.1

    func detectTrends(
        recoveries: [DailyRecovery],
        days: Int
    ) -> [RecoveryInsight] {
        guard recoveries.count >= 3 else {
            return []
        }

        let sorted = recoveries.sorted { $0.date < $1.date }
        let window = Array(sorted.suffix(days))
        var insights: [RecoveryInsight] = []

        // Pattern: HRV declining 3+ consecutive days
        if let hrvInsight = detectHRVDecline(window) {
            insights.append(hrvInsight)
        }

        // Pattern: Recovery improving trend
        if let improvingInsight = detectRecoveryTrend(window) {
            insights.append(improvingInsight)
        }

        // Pattern: Sleep consistency issue
        if let sleepInsight = detectSleepInconsistency(window) {
            insights.append(sleepInsight)
        }

        // Pattern: Strain-recovery correlation
        if let strainInsight = detectHighStrainPattern(window) {
            insights.append(strainInsight)
        }

        return insights
    }

    // MARK: - Training Prescription

    // Per MODULE_RECOVERY.md Section 8.2

    private struct TrainingResult {
        let zone: String
        let headline: String
        let body: String
    }

    private func generateTrainingPrescription(
        recoveryScore: Int,
        sleepHours: Double,
        sleepEfficiency: Double,
        sleepDebt: Double,
        yesterdayStrain: Double,
        schedule: [CalendarEvent]
    ) -> TrainingResult {
        // Step 1: Determine base zone
        // Per MODULE_RECOVERY.md Section 8.2
        var zoneLevel = switch recoveryScore {
        case 85 ... 100: 5 // peakGreen
        case 67 ... 84: 4 // green
        case 50 ... 66: 3 // upperYellow
        case 34 ... 49: 2 // lowerYellow
        case 20 ... 33: 1 // upperRed
        default: 0 // red
        }

        // Step 2: Apply modifiers (each can downgrade by 1)

        // Modifier D: Poor sleep (< 6h or efficiency < 75%)
        if sleepHours < 6.0 || sleepEfficiency < 75.0 {
            zoneLevel = max(0, zoneLevel - 1)
        }

        // Modifier E: Sleep debt > 4h
        if sleepDebt > 4.0 {
            zoneLevel = max(0, zoneLevel - 1)
        }

        // Modifier C: Football proximity
        if hasFootballTomorrow(schedule) {
            zoneLevel = min(zoneLevel, 3) // cap at upperYellow
        }

        // Step 3: Minimum is 0 (red/rest)
        zoneLevel = max(0, zoneLevel)

        // Step 4: Generate output per zone with specific prescriptions
        // Per MODULE_RECOVERY.md Training Zone Outputs table
        let sleepContext = sleepHours < 6 ?
            " Your sleep was short (\(String(format: "%.1f", sleepHours))h) — factor that into your effort." : ""
        let debtContext = sleepDebt > 2 ? " You're carrying \(String(format: "%.1f", sleepDebt))h of sleep debt." : ""
        let strainContext = yesterdayStrain > 14 ?
            " Yesterday's strain was high (\(String(format: "%.1f", yesterdayStrain))) — your nervous system may still be fatigued." : ""

        switch zoneLevel {
        case 5:
            return TrainingResult(
                zone: "peakGreen",
                headline: "Peak state — target strain 14-18 today",
                body: "HRV is elevated and recovery is excellent. This is the day for PRs, heavy compound lifts (4-5 working sets), or your hardest interval session. Target strain 14-18. Go for progressive overload — add 2.5-5kg to your main lifts or increase rep ranges.\(sleepContext)"
            )
        case 4:
            return TrainingResult(
                zone: "green",
                headline: "Full send — target strain 12-16 today",
                body: "Recovery supports high-volume training. Hit your planned workout at full intensity with 4 working sets per exercise. Target strain 12-16. Compound movements first, then accessories. You can push close to failure on the last set.\(sleepContext)"
            )
        case 3:
            return TrainingResult(
                zone: "upperYellow",
                headline: "Moderate day — reduce working sets from 4 to 3",
                body: "Solid recovery but not peak. Keep your planned weights but reduce working sets from 4 to 3. Drop weight 10% on accessories. Target strain 10-13. Focus on quality reps with controlled eccentrics.\(strainContext)\(debtContext)"
            )
        case 2:
            return TrainingResult(
                zone: "lowerYellow",
                headline: "Light session — drop weight 10%, cut sets to 3",
                body: "Recovery is below average. Reduce working weight by 10% and cap at 3 sets per exercise. Skip isolation accessories entirely. Target strain 8-11. Keep RPE at 6-7 max — no sets to failure.\(strainContext)\(debtContext)"
            )
        case 1:
            return TrainingResult(
                zone: "upperRed",
                headline: "Active recovery only — 20-minute walk, yoga, or light stretching",
                body: "Your body needs recovery. Choose ONE: a 20-minute easy walk (HR below 120bpm), a 15-minute yoga flow, or 20 minutes of light stretching and foam rolling. No resistance training. Target strain under 6.\(strainContext)\(sleepContext)"
            )
        default:
            return TrainingResult(
                zone: "red",
                headline: "Full rest day — zero structured training",
                body: "Recovery is very low. Take a complete rest day. If you must move, limit to a casual 10-15 minute walk. Focus entirely on sleep (aim for 9+ hours tonight), nutrition (extra protein and whole foods), and hydration (3+ liters). Your body is telling you to stop.\(strainContext)\(sleepContext)\(debtContext)"
            )
        }
    }

    // MARK: - Sleep Prescription

    // Per MODULE_RECOVERY.md Section 8.4

    private struct SleepResult {
        let bedtime: Date?
        let caffeineCutoff: Date?
    }

    private func generateSleepPrescription(
        sleepDebt: Double,
        yesterdayStrain: Double,
        wakeTimeMinutes: Int
    ) -> SleepResult {
        // Step 1: Target sleep duration
        // Per MODULE_RECOVERY.md: base 7.5h (Watson et al., 2015 AASM consensus)
        let baselineNeed = 7.5

        // Sleep debt repayment: max 1h/night (per MODULE_RECOVERY.md Section 8.4)
        let debtRepayment = min(sleepDebt, 1.0)

        // Strain adjustment: high strain yesterday adds 15-30 min
        let strainAdjustment: Double = switch yesterdayStrain {
        case 0 ..< 10: 0
        case 10 ..< 14: 0.25 // 15 min
        case 14 ..< 18: 0.5 // 30 min
        default: 0.5 // cap at 30 min
        }

        // Sleep debt acceleration: if debt > 2h, add 30min earlier bedtime
        let debtAcceleration: Double = sleepDebt > 2.0 ? 0.5 : 0.0

        let targetSleepDuration = baselineNeed + debtRepayment + strainAdjustment + debtAcceleration

        // Step 2: Calculate bedtime from wake time
        // Bedtime = wake_time - sleep_needed - sleep_onset_buffer(15min)
        let fallAsleepBuffer = 0.25 // 15 min
        let totalHoursBeforeWake = targetSleepDuration + fallAsleepBuffer

        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let wakeHour = wakeTimeMinutes / 60
        let wakeMinute = wakeTimeMinutes % 60

        guard let wakeDate = calendar.date(
            bySettingHour: wakeHour,
            minute: wakeMinute,
            second: 0,
            of: tomorrow
        )
        else {
            return SleepResult(bedtime: nil, caffeineCutoff: nil)
        }

        let bedtime = wakeDate.addingTimeInterval(-totalHoursBeforeWake * 3600)

        // Step 3: Caffeine cutoff = 8h before bedtime
        // Per MODULE_RECOVERY.md Section 8.4 (Drake et al., 2013)
        let caffeineCutoff = bedtime.addingTimeInterval(-8 * 3600)

        return SleepResult(bedtime: bedtime, caffeineCutoff: caffeineCutoff)
    }

    // MARK: - Hydration Prescription

    // Per MODULE_RECOVERY.md Section 8.5

    // NOTE: this produces DailyPrescription.hydrationTargetMl, surfaced via
    // RecoveryViewModel.formattedHydration — which is currently NOT rendered by
    // any view. The hydration number the user sees comes from NutritionEngine
    // (Fuel quadrant). If you ever wire this path into a view, route its
    // activity bonus through `HydrationMath` too, or the two surfaces will
    // disagree (the desync bug class Tempo's CLAUDE.md guards against).
    private func generateHydrationTarget(
        recoveryScore: Double,
        plannedTraining: Bool,
        bodyWeightKg: Double
    ) -> Int {
        // Step 1: Base = 35ml/kg (Sawka et al., 2007 ACSM)
        var totalMl = bodyWeightKg * 35

        // Step 2: Activity adjustment (+500ml per planned session)
        if plannedTraining {
            totalMl += 500
        }

        // Step 4: Recovery adjustment
        if recoveryScore < 50 {
            totalMl += 250
        }
        if recoveryScore < 30 {
            totalMl += 250 // total +500ml for very low recovery
        }

        return Int(totalMl)
    }

    // MARK: - Schedule Helpers

    private func hasPlannedTraining(_ schedule: [CalendarEvent]) -> Bool {
        let trainingKeywords = ["gym", "training", "workout", "crossfit", "weights", "run", "jog"]
        return schedule.contains { event in
            let title = event.title.lowercased()
            return trainingKeywords.contains(where: { title.contains($0) })
        }
    }

    private func hasFootballToday(_ schedule: [CalendarEvent]) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let footballKeywords = ["football", "soccer", "match", "game", "calcio", "partita"]
        return schedule.contains { event in
            let title = event.title.lowercased()
            let isToday = Calendar.current.isDate(event.startDate, inSameDayAs: today)
            return isToday && footballKeywords.contains(where: { title.contains($0) })
        }
    }

    private func hasFootballTomorrow(_ schedule: [CalendarEvent]) -> Bool {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else {
            return false
        }
        let footballKeywords = ["football", "soccer", "match", "game", "calcio", "partita"]
        return schedule.contains { event in
            let title = event.title.lowercased()
            let isTomorrow = Calendar.current.isDate(event.startDate, inSameDayAs: tomorrow)
            return isTomorrow && footballKeywords.contains(where: { title.contains($0) })
        }
    }

    // MARK: - Trend Detection Helpers

    private func detectHRVDecline(_ recoveries: [DailyRecovery]) -> RecoveryInsight? {
        // Check for 3+ consecutive days of HRV decline
        let hrvValues = recoveries.compactMap(\.hrvRmssd)
        guard hrvValues.count >= 3 else {
            return nil
        }

        let recent = Array(hrvValues.suffix(5))
        var consecutiveDeclines = 0

        for i in 1 ..< recent.count {
            if recent[i] < recent[i - 1] {
                consecutiveDeclines += 1
            } else {
                consecutiveDeclines = 0
            }
        }

        guard consecutiveDeclines >= 2 else {
            return nil
        }

        let firstHRV = recent[max(0, recent.count - consecutiveDeclines - 1)]
        let lastHRV = recent.last ?? firstHRV
        let dropPercent = ((firstHRV - lastHRV) / firstHRV) * 100

        return RecoveryInsight(
            date: Date(),
            type: .pattern,
            title: "HRV Declining",
            body: "Your HRV has dropped \(Int(dropPercent))% over the last \(consecutiveDeclines + 1) days. Consider a deload or extra rest day.",
            dataPointsJSON: encodeDataPoints(recent.enumerated().map { ["day": $0.offset + 1, "hrv": Int($0.element)] }),
            confidence: min(0.6 + Double(consecutiveDeclines) * 0.1, 0.95)
        )
    }

    private func detectRecoveryTrend(_ recoveries: [DailyRecovery]) -> RecoveryInsight? {
        guard recoveries.count >= 7 else {
            return nil
        }

        let scores = recoveries.map(\.recoveryScore)
        let firstHalf = Array(scores.prefix(scores.count / 2))
        let secondHalf = Array(scores.suffix(scores.count / 2))

        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
        let changePercent = ((secondAvg - firstAvg) / firstAvg) * 100

        guard abs(changePercent) > 10 else {
            return nil
        }

        let direction = changePercent > 0 ? "improving" : "declining"
        return RecoveryInsight(
            date: Date(),
            type: .pattern,
            title: "Recovery \(direction.capitalized)",
            body: "Your average recovery has \(direction) by \(Int(abs(changePercent)))% over this period. \(changePercent > 0 ? "Keep up the good work." : "Review your sleep and training load.")",
            confidence: min(0.5 + abs(changePercent) / 100, 0.9)
        )
    }

    private func detectSleepInconsistency(_ recoveries: [DailyRecovery]) -> RecoveryInsight? {
        let sleepHours = recoveries.compactMap(\.sleepHours)
        guard sleepHours.count >= 5 else {
            return nil
        }

        let avg = sleepHours.reduce(0, +) / Double(sleepHours.count)
        let variance = sleepHours.reduce(0.0) { $0 + pow($1 - avg, 2) } / Double(sleepHours.count)
        let stdDev = sqrt(variance)

        // High variability = > 1 hour standard deviation
        guard stdDev > 1.0 else {
            return nil
        }

        return RecoveryInsight(
            date: Date(),
            type: .recommendation,
            title: "Inconsistent Sleep",
            body: "Your sleep duration varies by over an hour night to night (avg \(String(format: "%.1f", avg))h ± \(String(format: "%.1f", stdDev))h). Consistent sleep timing improves recovery.",
            confidence: min(0.5 + stdDev * 0.2, 0.85)
        )
    }

    private func detectHighStrainPattern(_ recoveries: [DailyRecovery]) -> RecoveryInsight? {
        let paired = recoveries.compactMap { r -> (strain: Double, recovery: Double)? in
            guard let strain = r.strain else {
                return nil
            }
            return (strain: strain, recovery: r.recoveryScore)
        }
        guard paired.count >= 5 else {
            return nil
        }

        // Count days where high strain (>14) followed by low recovery (<50)
        let highStrainLowRecovery = paired.filter { $0.strain > 14 && $0.recovery < 50 }

        guard highStrainLowRecovery.count >= 3 else {
            return nil
        }

        return RecoveryInsight(
            date: Date(),
            type: .correlation,
            title: "High Strain Impact",
            body: "You've had \(highStrainLowRecovery.count) days with high strain (>14) and low recovery (<50%). Consider spacing out intense sessions.",
            confidence: Double(highStrainLowRecovery.count) / Double(paired.count)
        )
    }

    private func encodeDataPoints(_ points: [[String: Int]]) -> Data? {
        try? JSONSerialization.data(withJSONObject: points)
    }
}
