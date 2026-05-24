//
// TrainingEngineProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

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
        history: [ExerciseHistory]
    ) -> (weight: Double, reps: Int)

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
        split: TrainingSplit
    ) -> [WorkoutPlan]

    /// Returns true if the given date falls in a deload week based on training history.
    func isDeloadWeek(date: Date, deloadFrequencyWeeks: Int, trainingStartDate: Date?) -> Bool

    /// Returns the deload weight multiplier (e.g., 0.6 for 40% reduction).
    func deloadWeightMultiplier() -> Double
}
