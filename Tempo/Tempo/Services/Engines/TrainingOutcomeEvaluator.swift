//
// TrainingOutcomeEvaluator.swift
// Tempo
//
// Phase 4 (TRAINING_INTELLIGENCE_TO_10.md Fix 4.1) — outcome validation. This
// is what separates "personalized" (9) from "intelligent" (10): the system
// grades its OWN prescriptions and corrects. Once a week it scores the previous
// week — did the plan produce progress WITHOUT overreaching? — and that score
// feeds back into both the on-device profile and the AI program prompt.
//
// Pure + nonisolated → unit-testable with no device, network, or store.
//

import Foundation

/// The graded result of one training week.
struct WeekOutcome: Equatable, Sendable {
    /// Exercises whose best-set load increased vs. their prior session.
    let progressionHits: Int
    /// Sessions that overreached — entered RPE ≥ 9 OR a form breakdown.
    let overreachEvents: Int
    /// Planned training days with no logged session.
    let missedSessions: Int
    /// Net change in total weekly tonnage vs. the comparison set (kg).
    let netVolumeChange: Double
    /// 0…1 — progress WITHOUT overreach. The headline number; drives feedback.
    let qualityScore: Double
}

enum TrainingOutcomeEvaluator {
    /// Score the previous week. `lastWeek` is that week's saved ExerciseHistory
    /// rows; `plannedTrainingDays` is how many training days the plan scheduled
    /// (to detect missed sessions); `priorWeekVolume` is the tonnage of the week
    /// before (for the trend). All pure — caller supplies the data.
    static func evaluate(
        lastWeek: [ExerciseHistory],
        plannedTrainingDays: Int,
        priorWeekVolume: Double
    ) -> WeekOutcome {
        // Sessions = distinct training days actually logged.
        let loggedDays = Set(lastWeek.map { Calendar.current.startOfDay(for: $0.date) })
        let sessionCount = loggedDays.count
        let missed = max(0, plannedTrainingDays - sessionCount)

        // Overreach: a logged day where any exercise hit avgRPE ≥ 9 or broke form.
        var overreachDays = Set<Date>()
        for row in lastWeek where row.feedbackSampleCount > 0 {
            let day = Calendar.current.startOfDay(for: row.date)
            let highRPE = (row.avgRPE ?? 0) >= 9
            let formBroke = row.worstFormRaw
                .flatMap(FormQuality.init(rawValue:))?.isNegativeSignal ?? false
            if highRPE || formBroke { overreachDays.insert(day) }
        }
        let overreach = overreachDays.count

        // Progression: per-exercise, did the most recent best-set load beat the
        // earlier one within the week?
        let byExercise = Dictionary(grouping: lastWeek) { $0.exercise?.id }
        var progressionHits = 0
        for (exID, rows) in byExercise where exID != nil {
            let sorted = rows.sorted { $0.date < $1.date }
            guard let first = sorted.first?.bestSetWeight,
                  let last = sorted.last?.bestSetWeight,
                  sorted.count >= 2 else { continue }
            if last > first { progressionHits += 1 }
        }

        let weekVolume = lastWeek.reduce(0.0) { $0 + $1.totalVolume }
        let netVolumeChange = weekVolume - priorWeekVolume

        let quality = qualityScore(
            sessionCount: sessionCount,
            plannedTrainingDays: plannedTrainingDays,
            progressionHits: progressionHits,
            overreach: overreach,
            missed: missed
        )

        return WeekOutcome(
            progressionHits: progressionHits,
            overreachEvents: overreach,
            missedSessions: missed,
            netVolumeChange: netVolumeChange,
            qualityScore: quality
        )
    }

    /// Quality = progress, penalized by overreach and missed sessions. Bounded
    /// 0…1. A week with progression and zero overreach scores high; a week that
    /// progressed but overreached, or missed sessions, is penalized.
    static func qualityScore(
        sessionCount: Int,
        plannedTrainingDays: Int,
        progressionHits: Int,
        overreach: Int,
        missed: Int
    ) -> Double {
        guard sessionCount > 0 else { return 0 }

        // Adherence: fraction of planned sessions actually done.
        let adherence = plannedTrainingDays > 0
            ? Double(sessionCount) / Double(plannedTrainingDays)
            : 1.0

        // Progress component: fraction of logged sessions that produced a PR/bump.
        let progress = min(1.0, Double(progressionHits) / Double(max(1, sessionCount)))

        // Overreach penalty: each overreach day costs, capped so it can't go
        // negative on its own.
        let overreachPenalty = min(1.0, Double(overreach) / Double(max(1, sessionCount)))

        // Weighted blend: progress is the reward, overreach the main penalty,
        // adherence gates the whole thing.
        let raw = (0.6 * progress + 0.4 * min(1.0, adherence)) * (1.0 - 0.5 * overreachPenalty)
        return max(0, min(1, raw))
    }
}
