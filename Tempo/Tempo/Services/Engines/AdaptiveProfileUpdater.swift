//
// AdaptiveProfileUpdater.swift
// Tempo
//
// Phase 3 (TRAINING_INTELLIGENCE_TO_10.md Fix 3.2) — the learning rule.
// Runs on each saved session and nudges the AdaptiveProfile. "Learning" here
// is bounded online statistics, not a trained net — every update is small,
// clamped, and reversible, so the profile converges over weeks and can never
// make a wild jump. Pure + deterministic → fully unit-testable with no device.
//

import Foundation

enum AdaptiveProfileUpdater {
    // MARK: - Tunables (single source of truth, shared with tests)

    /// Sessions at/below this mean RPE are "easy" → learn a bigger increment.
    static let easyRPE: Double = 6.0
    /// Sessions at/above this mean RPE are "hard" → learn a smaller increment.
    static let hardRPE: Double = 8.5

    /// Multiplicative nudge per easy/hard session, with an absolute cap so a
    /// single session moves the increment at most this many kg.
    static let nudgeFactorUp: Double = 1.1
    static let nudgeFactorDown: Double = 0.9
    static let maxStepKg: Double = 1.0

    /// Hard floor/ceiling on any learned increment (kg). Keeps the increment in
    /// a sane lifting range regardless of how many sessions push it.
    static let minIncrement: Double = 1.0
    static let maxIncrement: Double = 10.0

    /// EWMA smoothing for the fatigue trend (0…1; higher = more reactive).
    static let fatigueAlpha: Double = 0.3

    /// Per-session threshold-offset nudge (points) and its clamp lives on
    /// AdaptiveProfile (±10). Small so it takes weeks to move meaningfully.
    static let thresholdStep: Double = 0.5

    // MARK: - Ingest

    /// Update `profile` in place from one saved session's `ExerciseHistory`
    /// rows. Only rows carrying real entered feedback (feedbackSampleCount > 0)
    /// move the learned signals — no-signal sessions leave the profile untouched.
    static func ingest(
        session: [ExerciseHistory],
        baseIncrement: (ExerciseHistory) -> Double,
        into profile: AdaptiveProfile
    ) {
        var sawSignal = false
        var sessionRPEs: [Double] = []

        for row in session {
            guard row.feedbackSampleCount > 0, let rpe = row.avgRPE else { continue }
            sawSignal = true
            sessionRPEs.append(rpe)

            guard let exID = row.exercise?.id else { continue }
            let current = profile.learnedIncrements[exID] ?? baseIncrement(row)

            let formBroke = row.worstFormRaw
                .flatMap(FormQuality.init(rawValue:))?.isNegativeSignal ?? false

            if rpe <= easyRPE, !formBroke {
                // Easy + clean → learn a bigger step (bounded).
                let raised = min(current * nudgeFactorUp, current + maxStepKg)
                profile.learnedIncrements[exID] = clampIncrement(raised)
            } else if rpe >= hardRPE || formBroke {
                // Hard or form broke → learn a smaller step (bounded).
                let lowered = max(current * nudgeFactorDown, current - maxStepKg)
                profile.learnedIncrements[exID] = clampIncrement(lowered)
            }
            // Middle band → no change (the increment is well-matched).
        }

        guard sawSignal else { return }

        // Fatigue EWMA across the session's mean RPE.
        let sessionMeanRPE = sessionRPEs.reduce(0, +) / Double(sessionRPEs.count)
        if let prior = profile.fatigueEWMA {
            profile.fatigueEWMA = fatigueAlpha * sessionMeanRPE + (1 - fatigueAlpha) * prior
        } else {
            profile.fatigueEWMA = sessionMeanRPE
        }

        // Threshold offset: a string of easy sessions earns a small NEGATIVE
        // offset (this user handles lower recovery well → green starts lower);
        // hard/overreaching sessions push it positive (be more conservative).
        if sessionMeanRPE <= easyRPE {
            profile.recoveryThresholdOffset = clampOffset(
                profile.recoveryThresholdOffset - thresholdStep
            )
        } else if sessionMeanRPE >= hardRPE {
            profile.recoveryThresholdOffset = clampOffset(
                profile.recoveryThresholdOffset + thresholdStep
            )
        }

        profile.updatedAt = Date()
    }

    // MARK: - Clamps

    static func clampIncrement(_ value: Double) -> Double {
        min(max(value, minIncrement), maxIncrement)
    }

    static func clampOffset(_ value: Double) -> Double {
        min(max(value, AdaptiveProfile.minThresholdOffset), AdaptiveProfile.maxThresholdOffset)
    }
}
