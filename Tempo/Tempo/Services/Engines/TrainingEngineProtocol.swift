//
// TrainingEngineProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - ProgressionDecision

/// Result of a progressive-overload calculation. Carries not just the next
/// (weight, reps) but the signed change applied and WHY — so the exercise card
/// can show a "why" string and tests can assert on the decision path.
///
/// Replaces the old `(weight: Double, reps: Int)` tuple. The two members keep
/// the same names so existing `overload.weight` / `overload.reps` call sites
/// compile unchanged.
struct ProgressionDecision: Equatable, Sendable {
    let weight: Double
    let reps: Int
    /// Signed kg change vs. the current working weight (0 when held).
    let deltaApplied: Double
    let rationale: ProgressionReason
}

/// Why the progression engine made its call. Drives the user-facing "why"
/// copy and is the assertion surface for the Phase-1 tests.
enum ProgressionReason: String, Equatable, Sendable, Codable {
    /// Low RPE + clean form + reps to spare → double the increment (clamped).
    case acceleratedEasyLoad
    /// 2-of-3 sessions hit target at normal RPE → standard increment.
    case standardProgression
    /// Most recent entered feedback was maximal (avgRPE ≥ 9) → hold.
    case heldHighRPE
    /// Most recent entered feedback showed sloppy/failed form → hold.
    case heldBrokenForm
    /// Fewer than 2 sessions of history → hold at last known weight.
    case heldInsufficientData
    /// Failed 3 sessions in a row well below target → step weight down.
    case deloadedRepeatedFailure
}

protocol TrainingEngineProtocol: Sendable {
    func generateWorkout(
        for date: Date,
        recoveryScore: Double?,
        footballDays: ActiveDays,
        split: TrainingSplit
    ) -> WorkoutPlan

    func adjustForRecovery(plan: WorkoutPlan, score: Double) -> WorkoutPlan

    func calculateProgressiveOverload(
        for exercise: Exercise,
        history: [ExerciseHistory],
        learnedIncrement: Double?
    ) -> ProgressionDecision

    /// Rest-time multiplier reflecting recent conditioning debt. When recent
    /// sessions repeatedly gassed the user (`gassedFraction` high), rest is
    /// lengthened even at green recovery — recovery score ≠ work capacity.
    /// Returns 1.0 when there's no conditioning-debt signal.
    func restMultiplier(history: [ExerciseHistory]) -> Double

    func detectPersonalRecord(
        exercise: Exercise,
        weight: Double,
        reps: Int
    ) -> PersonalRecord?

    /// Generates a week's worth of WorkoutPlans starting Monday.
    /// `recoveryScores` is a per-day map (key = startOfDay for that date); a
    /// missing day falls through to the green/unknown branch. Pass an empty
    /// map for environments without recovery data.
    func generateWeekPlan(
        startDate: Date,
        recoveryScores: [Date: Double],
        footballDays: ActiveDays,
        split: TrainingSplit,
        recoveryThresholdOffset: Double,
        // D3 — start-of-day keys of dated matches (§14 mid-week-match trigger).
        matchDayKeys: Set<Date>
    ) -> [WorkoutPlan]

    /// Returns true if the given date falls in a deload week. The fixed periodic
    /// schedule is the baseline; a rising fatigue trend (`fatigueEWMA`) can
    /// trigger an EARLY deload. Pass nil for `fatigueEWMA` to use the periodic
    /// schedule only.
    func isDeloadWeek(
        date: Date,
        deloadFrequencyWeeks: Int,
        trainingStartDate: Date?,
        fatigueEWMA: Double?
    ) -> Bool

    /// Returns the deload weight multiplier (e.g., 0.6 for 40% reduction).
    func deloadWeightMultiplier() -> Double
}
