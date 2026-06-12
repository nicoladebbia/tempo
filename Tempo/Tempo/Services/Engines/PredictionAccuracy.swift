//
// PredictionAccuracy.swift
// Tempo
//
// Step 2 (measurement spine) — turn the raw prediction↔reality pairs from
// PredictionLog into the one number that defines "intelligent" under the
// user's own definition ("adapts correctly to my data over time"): how far
// off were the engine's predictions, and is that error SHRINKING?
//
// Pure + nonisolated → testable with no device/store. Reads only RESOLVED rows
// that carry an actual RPE; everything else is "no signal" and excluded — never
// counted as zero error. Still PASSIVE: this measures, it does not prescribe.
//

import Foundation

/// Direction of the error trend over time. The whole point of the system.
enum AccuracyTrend: String, Equatable, Sendable {
    case improving   // recent error meaningfully smaller than prior
    case stable      // within noise
    case worsening   // recent error meaningfully larger than prior
    case insufficient // not enough resolved data to judge
}

/// Accuracy for one exercise.
struct ExerciseAccuracy: Equatable, Sendable {
    let exerciseID: UUID
    /// Mean ABSOLUTE RPE error across the scored window (|actual − predicted|).
    let meanAbsError: Double
    /// Mean SIGNED RPE error — tells direction: positive = systematically
    /// over-prescribing (too hard), negative = under-prescribing (too easy).
    let meanSignedError: Double
    let sampleCount: Int
    let trend: AccuracyTrend
}

/// Whole-system accuracy summary.
struct AccuracySummary: Equatable, Sendable {
    let overallMeanAbsError: Double
    let overallTrend: AccuracyTrend
    let totalScored: Int
    let perExercise: [ExerciseAccuracy]

    static let empty = AccuracySummary(
        overallMeanAbsError: 0, overallTrend: .insufficient, totalScored: 0, perExercise: []
    )
}

/// Verdict of the personalized-vs-generic hold-out (Step 4). The honest check:
/// does personalization actually beat the dumb baseline, or is it theater?
enum HoldoutVerdict: String, Equatable, Sendable {
    case personalizedWins   // personalized error meaningfully lower than baseline
    case tie                // within noise — no demonstrated advantage
    case baselineWins       // personalized is WORSE than just +2.5kg/week
    case insufficient       // not enough resolved rows with a baseline
}

/// Result of comparing the personalized engine's prediction error against the
/// generic baseline's ESTIMATED error over the same sessions.
struct HoldoutResult: Equatable, Sendable {
    let personalizedMeanAbsError: Double
    let baselineMeanAbsError: Double
    let sampleCount: Int
    let verdict: HoldoutVerdict

    static let insufficient = HoldoutResult(
        personalizedMeanAbsError: 0, baselineMeanAbsError: 0,
        sampleCount: 0, verdict: .insufficient
    )
}

/// One resolved SESSION-level pair (§14 #3): the brain's expectedSessionRPE
/// (DailySession) vs the user's one-tap actual (WorkoutPlan.sessionRPE).
/// Same spine as PredictionLog, one level up — whole session, not per set.
struct SessionRPEPair: Equatable, Sendable {
    let date: Date
    let expected: Int
    let actual: Int
    /// Signed error: positive = session felt HARDER than predicted.
    var error: Double { Double(actual - expected) }
}

/// Session-level accuracy summary. Mirrors ExerciseAccuracy semantics.
struct SessionRPEAccuracy: Equatable, Sendable {
    let meanAbsError: Double
    /// Positive = brain systematically under-calls the cost (sessions feel
    /// harder than predicted); negative = over-calls it.
    let meanSignedError: Double
    let sampleCount: Int
    let trend: AccuracyTrend

    static let empty = SessionRPEAccuracy(
        meanAbsError: 0, meanSignedError: 0, sampleCount: 0, trend: .insufficient
    )
}

enum PredictionAccuracy {
    /// A trend is called only when each window has at least this many scored
    /// rows — below that, error is too noisy to read as a direction.
    static let minWindow = 3
    /// Recent-vs-prior mean-abs-error must change by more than this (RPE points)
    /// to count as improving/worsening rather than stable.
    static let trendEpsilon = 0.3

    /// Build the summary from prediction rows. Only resolved rows with an actual
    /// RPE are scored. Rows are ordered by date so the trend split is by time.
    static func summarize(_ logs: [PredictionLog]) -> AccuracySummary {
        let scored = logs
            .filter { $0.outcomeResolved && $0.actualRPE != nil }
            .sorted { $0.date < $1.date }
        guard !scored.isEmpty else { return .empty }

        let overallAbs = mean(scored.map { abs($0.rpeError ?? 0) })
        let overallTrend = trend(of: scored)

        // Per-exercise breakdown.
        let byExercise = Dictionary(grouping: scored, by: { $0.exerciseID })
        let perExercise = byExercise.map { exID, rows -> ExerciseAccuracy in
            let sortedRows = rows.sorted { $0.date < $1.date }
            return ExerciseAccuracy(
                exerciseID: exID,
                meanAbsError: mean(sortedRows.map { abs($0.rpeError ?? 0) }),
                meanSignedError: mean(sortedRows.map { $0.rpeError ?? 0 }),
                sampleCount: sortedRows.count,
                trend: trend(of: sortedRows)
            )
        }
        .sorted { $0.meanAbsError > $1.meanAbsError } // worst-predicted first

        return AccuracySummary(
            overallMeanAbsError: overallAbs,
            overallTrend: overallTrend,
            totalScored: scored.count,
            perExercise: perExercise
        )
    }

    /// Hold-out: how much smaller is personalized error than the generic
    /// baseline's estimated error, over rows that have BOTH a real error and a
    /// baseline estimate? `minWindow` rows required to call a verdict. The
    /// baseline must beat personalized by more than `trendEpsilon` to flip the
    /// verdict — ties are honest "no demonstrated advantage", not a win.
    static func holdout(_ logs: [PredictionLog]) -> HoldoutResult {
        let scored = logs.filter {
            $0.outcomeResolved && $0.rpeError != nil && $0.baselineRPEErrorEstimate != nil
        }
        guard scored.count >= minWindow else { return .insufficient }

        let personalized = mean(scored.map { abs($0.rpeError ?? 0) })
        let baseline = mean(scored.map { abs($0.baselineRPEErrorEstimate ?? 0) })
        let delta = personalized - baseline // negative = personalized better

        let verdict: HoldoutVerdict
        if delta < -trendEpsilon {
            verdict = .personalizedWins
        } else if delta > trendEpsilon {
            verdict = .baselineWins
        } else {
            verdict = .tie
        }
        return HoldoutResult(
            personalizedMeanAbsError: personalized,
            baselineMeanAbsError: baseline,
            sampleCount: scored.count,
            verdict: verdict
        )
    }

    /// Session-level accuracy (§14 #3). Only pairs where BOTH sides exist are
    /// scored — the caller filters; a missing actual is "no signal", never zero.
    static func summarizeSessions(_ pairs: [SessionRPEPair]) -> SessionRPEAccuracy {
        guard !pairs.isEmpty else { return .empty }
        let sorted = pairs.sorted { $0.date < $1.date }
        let errors = sorted.map(\.error)
        return SessionRPEAccuracy(
            meanAbsError: mean(errors.map(abs)),
            meanSignedError: mean(errors),
            sampleCount: sorted.count,
            trend: trend(absErrors: errors.map(abs))
        )
    }

    // MARK: - Internals

    /// Split the (date-sorted) rows into prior/recent halves and compare mean
    /// absolute error. Improving = recent meaningfully lower than prior.
    static func trend(of sortedScored: [PredictionLog]) -> AccuracyTrend {
        trend(absErrors: sortedScored.map { abs($0.rpeError ?? 0) })
    }

    /// Same prior/recent split over a date-sorted abs-error series — shared by
    /// the per-exercise and session-level spines.
    static func trend(absErrors: [Double]) -> AccuracyTrend {
        guard absErrors.count >= minWindow * 2 else { return .insufficient }
        let mid = absErrors.count / 2
        let priorErr = mean(Array(absErrors[..<mid]))
        let recentErr = mean(Array(absErrors[mid...]))
        let delta = recentErr - priorErr
        if delta < -trendEpsilon { return .improving }
        if delta > trendEpsilon { return .worsening }
        return .stable
    }

    static func mean(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }
}
