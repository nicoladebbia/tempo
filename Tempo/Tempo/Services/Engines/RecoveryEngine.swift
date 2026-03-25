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
        if strain > 18 && score < 67 {
            warnings.append("Yesterday's strain was very high (\(String(format: "%.1f", strain))) with below-average recovery. Take it easy.")
        }

        // Warning: Very low recovery
        if score < 34 {
            warnings.append("Recovery is in the red zone. If you experience persistent low recovery for 7+ days, consider consulting a healthcare professional.")
        }

        logger.info("Generated prescription: zone=\(training.zone), hydration=\(hydrationMl)ml, warnings=\(warnings.count)")

        return DailyPrescription(
            date: recovery.date,
            trainingRec: training.headline,
            trainingDetail: training.body,
            nutritionRecs: nutritionRecs,
            bedtimeTarget: sleepRx.bedtime,
            caffeineCutoff: sleepRx.caffeineCutoff,
            hydrationTargetMl: hydrationMl,
            warnings: warnings,
            dailyRecovery: recovery
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
        guard !recentSleep.isEmpty else { return 0 }

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
        guard recoveries.count >= 3 else { return [] }

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
        var zoneLevel: Int
        switch recoveryScore {
        case 85...100: zoneLevel = 5 // peakGreen
        case 67...84:  zoneLevel = 4 // green
        case 50...66:  zoneLevel = 3 // upperYellow
        case 34...49:  zoneLevel = 2 // lowerYellow
        case 20...33:  zoneLevel = 1 // upperRed
        default:       zoneLevel = 0 // red
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

        // Step 4: Generate output per zone
        // Per MODULE_RECOVERY.md Training Zone Outputs table
        switch zoneLevel {
        case 5:
            return TrainingResult(
                zone: "peakGreen",
                headline: "Peak state — push your limits today",
                body: "HRV is elevated and recovery is excellent. This is the day for PRs, heavy compound lifts, or your hardest interval session. Train with intent — but always with proper form and warm-up."
            )
        case 4:
            return TrainingResult(
                zone: "green",
                headline: "Full send — compound lifts and PRs OK",
                body: "Recovery supports high-volume training. Hit your planned workout at full intensity."
            )
        case 3:
            return TrainingResult(
                zone: "upperYellow",
                headline: "Moderate day — reduce volume 20%",
                body: "Solid recovery but not peak. Train at normal intensity but cut total sets/reps by about 20%. Focus on quality reps."
            )
        case 2:
            return TrainingResult(
                zone: "lowerYellow",
                headline: "Easy-moderate — maintain intensity, cut volume 30%",
                body: "Recovery is below average. Keep weights the same but reduce total volume by 30%. Skip accessory work if needed."
            )
        case 1:
            return TrainingResult(
                zone: "upperRed",
                headline: "Easy day — mobility, stretching, or light cardio",
                body: "Your body needs recovery. Stick to mobility work, yoga, a light walk, or easy swimming. Avoid resistance training."
            )
        default:
            return TrainingResult(
                zone: "red",
                headline: "Rest day — full recovery",
                body: "Recovery is very low. Take a complete rest day. Light walking is fine but avoid structured training. Focus on sleep, nutrition, and hydration."
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
        let baselineNeed: Double = 7.5

        // Sleep debt repayment: max 1h/night (per MODULE_RECOVERY.md Section 8.4)
        let debtRepayment = min(sleepDebt, 1.0)

        // Strain adjustment: high strain yesterday adds 15-30 min
        let strainAdjustment: Double
        switch yesterdayStrain {
        case 0..<10:   strainAdjustment = 0
        case 10..<14:  strainAdjustment = 0.25  // 15 min
        case 14..<18:  strainAdjustment = 0.5   // 30 min
        default:       strainAdjustment = 0.5   // cap at 30 min
        }

        let targetSleepDuration = baselineNeed + debtRepayment + strainAdjustment

        // Step 2: Calculate bedtime from wake time
        let fallAsleepBuffer: Double = 0.25 // 15 min
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
        ) else {
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
        let hrvValues = recoveries.compactMap { $0.hrvRmssd }
        guard hrvValues.count >= 3 else { return nil }

        let recent = Array(hrvValues.suffix(5))
        var consecutiveDeclines = 0

        for i in 1..<recent.count {
            if recent[i] < recent[i - 1] {
                consecutiveDeclines += 1
            } else {
                consecutiveDeclines = 0
            }
        }

        guard consecutiveDeclines >= 2 else { return nil }

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
        guard recoveries.count >= 7 else { return nil }

        let scores = recoveries.map(\.recoveryScore)
        let firstHalf = Array(scores.prefix(scores.count / 2))
        let secondHalf = Array(scores.suffix(scores.count / 2))

        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
        let changePercent = ((secondAvg - firstAvg) / firstAvg) * 100

        guard abs(changePercent) > 10 else { return nil }

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
        guard sleepHours.count >= 5 else { return nil }

        let avg = sleepHours.reduce(0, +) / Double(sleepHours.count)
        let variance = sleepHours.reduce(0.0) { $0 + pow($1 - avg, 2) } / Double(sleepHours.count)
        let stdDev = sqrt(variance)

        // High variability = > 1 hour standard deviation
        guard stdDev > 1.0 else { return nil }

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
            guard let strain = r.strain else { return nil }
            return (strain: strain, recovery: r.recoveryScore)
        }
        guard paired.count >= 5 else { return nil }

        // Count days where high strain (>14) followed by low recovery (<50)
        let highStrainLowRecovery = paired.filter { $0.strain > 14 && $0.recovery < 50 }

        guard highStrainLowRecovery.count >= 3 else { return nil }

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
