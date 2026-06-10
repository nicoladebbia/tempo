//
// MonthlyReviewAggregator.swift
// Tempo
//
// D4 §17.2 — turns a month of raw rows into the numbers the Sonnet summary
// is ALLOWED to talk about. Pure + nonisolated (snapshot inputs, like
// ReadinessAssembler) so every number is unit-testable without SwiftData.
//
// Two §12 honesty rules are enforced HERE, not left to the prompt:
//   • G5 — body comp uses ReadinessTrendMath.robustDelta (rolling median +
//     fitted slope), never month-end point-to-point. Below 10 samples the
//     delta is nil and the gap is stated.
//   • §15.2 — floor-forced and venue-unavailable skips stay OUT of the
//     adherence denominator. Only user skips count against him.
//
// The aggregator also assembles the "honest gaps" list (§17.2) — missing
// Whoop days, thin body-comp data, unrated sessions — so the report states
// what it doesn't know instead of sounding confident about it.
//

import Foundation

// MARK: - Input snapshots (decouple from @Model, ViewModel maps)

struct MonthPlanSnapshot: Equatable, Sendable {
    let date: Date
    /// WorkoutType.displayName ("Push", "Football", …).
    let typeDisplayName: String
    let statusRaw: String
    let skipReasonRaw: String?
    let startedAt: Date?
    /// Completed gym tonnage (kg); 0 for non-gym.
    let tonnageKg: Double
    let sessionRPE: Int?
}

struct MonthBodySample: Equatable, Sendable {
    let date: Date
    let weightKg: Double?
    let bodyFatPercent: Double?
    let leanMassKg: Double?
}

struct MonthRecoverySample: Equatable, Sendable {
    let date: Date
    let hrv: Double?
    let rhr: Double?
    let recoveryScore: Double
}

struct MonthPRSnapshot: Equatable, Sendable {
    /// Already-formatted highlight, e.g. "Bench Press 1RM 102.5kg".
    let label: String
    let date: Date
}

/// The §17.1 interview answers, snapshotted off the MonthlyReview row.
struct MonthInterviewSnapshot: Equatable, Sendable {
    var wentWell: String? = nil
    var struggles: String? = nil
    var niggles: String? = nil
    var subjectiveProgress: String? = nil
    var goalsNextMonth: String? = nil
    var chosenEmphasis: String? = nil
}

// MARK: - Output

struct MonthlyReviewData: Equatable, Sendable {
    let monthKey: String
    let daysInMonth: Int

    // Training (§17.2 bullet 1)
    let completedByModality: [String: Int]
    let completedTotal: Int
    let userSkipped: Int
    let floorForcedSkips: Int
    /// completed / (completed + userSkipped) × 100. nil when nothing was
    /// prescribed — no denominator, no claim.
    let adherencePct: Int?
    /// Median start hour (0–23) of completed sessions with a startedAt.
    let typicalStartHour: Int?

    // Strength (§17.2 bullet 2)
    let totalTonnageKg: Double
    /// Tonnage per ISO week, chronological — the trend shape for the report.
    let weeklyTonnageKg: [Double]
    let prHighlights: [String]
    let prCount: Int

    // Body comp (§17.2 bullet 3 — G5 robust deltas, nil = insufficient)
    let weightDeltaKg: Double?
    let bodyFatDeltaPct: Double?
    let leanMassDeltaKg: Double?
    let bodySampleCount: Int

    // Readiness (§17.2 bullet 4 — month-edge baseline shifts)
    let hrvShift: Double?
    let rhrShift: Double?
    let avgRecoveryScore: Double?

    // Calibration (the accuracy spine, exercise + session level)
    let exerciseAccuracy: AccuracySummary
    let sessionAccuracy: SessionRPEAccuracy

    // Honest gaps (§17.2 bullet 5) — pre-formatted lines
    let gaps: [String]
}

// MARK: - Aggregator

enum MonthlyReviewAggregator {
    /// Body-comp robust trend needs at least this many weigh-ins (G5).
    static let minBodySamples = 10
    /// Missing-Whoop days are only worth calling out past this.
    static let whoopGapThreshold = 3

    static func aggregate(
        monthKey: String,
        daysInMonth: Int,
        plans: [MonthPlanSnapshot],
        bodySamples: [MonthBodySample],
        recoverySamples: [MonthRecoverySample],
        prs: [MonthPRSnapshot],
        exerciseAccuracy: AccuracySummary,
        sessionAccuracy: SessionRPEAccuracy,
        calendar: Calendar = .current
    ) -> MonthlyReviewData {
        // Training — terminal rows only; §15.2 split on skip reason.
        let completed = plans.filter { $0.statusRaw == WorkoutStatus.completed.rawValue }
        let skipped = plans.filter { $0.statusRaw == WorkoutStatus.skipped.rawValue }
        let userSkips = skipped.filter { $0.skipReasonRaw == SkipReason.userSkipped.rawValue }.count
        let floorSkips = skipped.filter { $0.skipReasonRaw == SkipReason.floorForced.rawValue }.count

        let byModality = Dictionary(grouping: completed, by: \.typeDisplayName)
            .mapValues(\.count)
        let denominator = completed.count + userSkips
        let adherence = denominator > 0
            ? Int((Double(completed.count) / Double(denominator) * 100).rounded())
            : nil

        let startHours = completed.compactMap { plan in
            plan.startedAt.map { Double(calendar.component(.hour, from: $0)) }
        }
        let typicalHour = ReadinessTrendMath.median(startHours).map { Int($0.rounded()) }

        // Strength
        let tonnage = completed.map(\.tonnageKg).reduce(0, +)
        let byWeek = Dictionary(grouping: completed) { plan in
            calendar.component(.weekOfYear, from: plan.date)
        }
        let weeklyTonnage = byWeek.keys.sorted().map { week in
            byWeek[week]!.map(\.tonnageKg).reduce(0, +)
        }

        // Body comp — G5: robust deltas over date-ordered series, never
        // point-to-point. Each metric needs its own sample count.
        let ordered = bodySamples.sorted { $0.date < $1.date }
        let weights = ordered.compactMap(\.weightKg)
        let fats = ordered.compactMap(\.bodyFatPercent)
        let leans = ordered.compactMap(\.leanMassKg)
        let weightDelta = ReadinessTrendMath.robustDelta(weights, minSamples: minBodySamples)
        let fatDelta = ReadinessTrendMath.robustDelta(fats, minSamples: minBodySamples)
        let leanDelta = ReadinessTrendMath.robustDelta(leans, minSamples: minBodySamples)

        // Readiness — month-edge median shifts (adapting = RHR down, HRV up).
        let recOrdered = recoverySamples.sorted { $0.date < $1.date }
        let hrvShift = ReadinessTrendMath.baselineShift(recOrdered.compactMap(\.hrv))
        let rhrShift = ReadinessTrendMath.baselineShift(recOrdered.compactMap(\.rhr))
        let recScores = recOrdered.map(\.recoveryScore)
        let avgRecovery = recScores.isEmpty ? nil : ReadinessTrendMath.mean(recScores)

        // Honest gaps (§17.2) — what the report must admit it can't claim.
        var gaps: [String] = []
        let whoopMissing = max(0, daysInMonth - recoverySamples.count)
        if whoopMissing > whoopGapThreshold {
            gaps.append("Whoop data missing for \(whoopMissing) of \(daysInMonth) days — readiness trends are partial.")
        }
        if weights.count < minBodySamples {
            gaps.append("Only \(weights.count) weigh-ins — body-comp trend not callable (need \(minBodySamples)+).")
        }
        let unrated = completed.filter { $0.sessionRPE == nil }.count
        if !completed.isEmpty, unrated > completed.count / 2 {
            gaps.append("\(unrated) of \(completed.count) sessions have no session-RPE rating — calibration signal is thin.")
        }
        if exerciseAccuracy.totalScored == 0, sessionAccuracy.sampleCount == 0 {
            gaps.append("No resolved prediction-vs-actual pairs this month — cannot judge prescription calibration.")
        }

        return MonthlyReviewData(
            monthKey: monthKey,
            daysInMonth: daysInMonth,
            completedByModality: byModality,
            completedTotal: completed.count,
            userSkipped: userSkips,
            floorForcedSkips: floorSkips,
            adherencePct: adherence,
            typicalStartHour: typicalHour,
            totalTonnageKg: tonnage,
            weeklyTonnageKg: weeklyTonnage,
            prHighlights: prs.sorted { $0.date < $1.date }.map(\.label),
            prCount: prs.count,
            weightDeltaKg: weightDelta,
            bodyFatDeltaPct: fatDelta,
            leanMassDeltaKg: leanDelta,
            bodySampleCount: weights.count,
            hrvShift: hrvShift,
            rhrShift: rhrShift,
            avgRecoveryScore: avgRecovery,
            exerciseAccuracy: exerciseAccuracy,
            sessionAccuracy: sessionAccuracy,
            gaps: gaps
        )
    }
}

// MARK: - Prompt (Sonnet, ≤1/month — §17.2)

enum MonthlyReviewPrompt {
    /// Same coach voice as the daily brain, but a REPORT, not a prescription.
    /// The honesty rules are restated because Sonnet only sees this text —
    /// every number it may use is in the user message; inventing others is
    /// the failure mode.
    static let system = """
    You are Tempo's monthly training coach — drill-sergeant direct, zero fluff. \
    Write Nicola's end-of-month report from the DATA and INTERVIEW blocks.

    Structure (plain text, these exact headers):
    TRAINING — sessions, adherence, what the skips say.
    STRENGTH — tonnage shape, PRs, how well prescriptions were calibrated (RPE error).
    BODY — the robust monthly deltas. These are trend-fitted, daily scale noise is already removed.
    READINESS — HRV/RHR baseline shifts: is he adapting or accumulating fatigue?
    GAPS — restate every line from the gaps block, verbatim meaning.
    NEXT MONTH — 2-3 concrete orders, tied to his stated goals and any chosen emphasis.

    Hard rules:
    - Use ONLY numbers present in the data block. Never invent or extrapolate a number.
    - A nil/absent metric means "not enough data" — say exactly that, don't guess.
    - Negative signed RPE error = prescriptions too easy; positive = too hard.
    - Max 300 words. No markdown, no emoji, no praise padding.
    """

    static func userMessage(data: MonthlyReviewData, interview: MonthInterviewSnapshot) -> String {
        var lines: [String] = []
        lines.append("MONTH: \(data.monthKey) (\(data.daysInMonth) days)")
        lines.append("")
        lines.append("DATA:")
        let modalities = data.completedByModality
            .sorted { $0.value > $1.value }
            .map { "\($0.key) ×\($0.value)" }
            .joined(separator: ", ")
        lines.append("- Completed: \(data.completedTotal) sessions (\(modalities.isEmpty ? "none" : modalities))")
        if let adherence = data.adherencePct {
            lines.append("- Adherence: \(adherence)% (\(data.userSkipped) user skips; \(data.floorForcedSkips) floor-forced rest days excluded — body said no, not him)")
        }
        if let hour = data.typicalStartHour {
            lines.append("- Typical session start: ~\(hour):00")
        }
        lines.append("- Total tonnage: \(Int(data.totalTonnageKg))kg; by week: \(data.weeklyTonnageKg.map { String(Int($0)) }.joined(separator: " → "))kg")
        if data.prCount > 0 {
            lines.append("- PRs (\(data.prCount)): \(data.prHighlights.joined(separator: "; "))")
        } else {
            lines.append("- PRs: none this month")
        }
        if data.exerciseAccuracy.totalScored > 0 {
            lines.append("- Set-level calibration: mean abs RPE error \(fmt(data.exerciseAccuracy.overallMeanAbsError)) over \(data.exerciseAccuracy.totalScored) sets, trend \(data.exerciseAccuracy.overallTrend.rawValue)")
        }
        if data.sessionAccuracy.sampleCount > 0 {
            lines.append("- Session-level calibration: mean abs sRPE error \(fmt(data.sessionAccuracy.meanAbsError)), signed \(fmt(data.sessionAccuracy.meanSignedError)) over \(data.sessionAccuracy.sampleCount) sessions, trend \(data.sessionAccuracy.trend.rawValue)")
        }
        lines.append("- Body comp (robust monthly trend, \(data.bodySampleCount) weigh-ins): weight \(fmtDelta(data.weightDeltaKg, "kg")), body-fat \(fmtDelta(data.bodyFatDeltaPct, "%")), lean mass \(fmtDelta(data.leanMassDeltaKg, "kg"))")
        lines.append("- Readiness baseline shift (month start → end): HRV \(fmtDelta(data.hrvShift, "ms")), RHR \(fmtDelta(data.rhrShift, "bpm"))\(data.avgRecoveryScore.map { ", avg recovery \(Int($0))/100" } ?? "")")
        lines.append("")
        lines.append("GAPS:")
        if data.gaps.isEmpty {
            lines.append("- none")
        } else {
            lines.append(contentsOf: data.gaps.map { "- \($0)" })
        }
        lines.append("")
        lines.append("INTERVIEW:")
        lines.append("- Went well: \(interview.wentWell ?? "(not answered)")")
        lines.append("- Struggles/skips: \(interview.struggles ?? "(not answered)")")
        lines.append("- Niggles/injuries: \(interview.niggles ?? "(not answered)")")
        lines.append("- Subjective progress: \(interview.subjectiveProgress ?? "(not answered)")")
        lines.append("- Goals next month: \(interview.goalsNextMonth ?? "(not answered)")")
        if let emphasis = interview.chosenEmphasis {
            lines.append("- Next month's declared emphasis: \(emphasis)")
        }
        return lines.joined(separator: "\n")
    }

    private static func fmt(_ x: Double) -> String {
        String(format: "%.1f", x)
    }

    private static func fmtDelta(_ x: Double?, _ unit: String) -> String {
        guard let x else { return "insufficient data" }
        return String(format: "%+.1f%@", x, unit)
    }
}

// MARK: - Schedule (when is a review due, and over which dates)

/// Pure month-window math. The review is OFFERED in a window around the month
/// boundary: the last `tailDays` of a month (reviewing that month) through the
/// first `graceDays` of the next (still reviewing the month that just ended).
/// Outside the window nothing renders — a monthly ritual, not a nag.
enum MonthlyReviewSchedule {
    static let tailDays = 3
    static let graceDays = 4

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// The month key due for review on `date`, or nil outside the window.
    static func dueMonthKey(on date: Date, calendar: Calendar = .current) -> String? {
        let day = calendar.component(.day, from: date)
        if day <= graceDays {
            guard let prev = calendar.date(byAdding: .month, value: -1, to: date) else { return nil }
            return monthKey(for: prev, calendar: calendar)
        }
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return nil }
        return day > range.count - tailDays ? monthKey(for: date, calendar: calendar) : nil
    }

    /// [start of month, start of next month) for fetch predicates.
    static func monthInterval(forKey key: String, calendar: Calendar = .current) -> DateInterval? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2,
              let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 1)),
              let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// First day of the month AFTER the reviewed one — where the interview's
    /// chosen emphasis becomes a TrainingBlock.
    static func nextMonthStart(afterKey key: String, calendar: Calendar = .current) -> Date? {
        monthInterval(forKey: key, calendar: calendar)?.end
    }
}
