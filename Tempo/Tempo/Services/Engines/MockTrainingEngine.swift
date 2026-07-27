//
// MockTrainingEngine.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

final class MockTrainingEngine: TrainingEngineProtocol, @unchecked Sendable {
    func generateWorkout(
        for date: Date,
        recoveryScore: Double?,
        footballDays: ActiveDays,
        split: TrainingSplit,
        customWeekdayMap: [WorkoutType]? = nil
    ) -> WorkoutPlan {
        WorkoutPlan(
            date: date,
            type: .push,
            status: .planned,
            notes: "Mock push workout"
        )
    }

    func calculateProgressiveOverload(
        for exercise: Exercise,
        history: [ExerciseHistory],
        learnedIncrement: Double? = nil
    ) -> ProgressionDecision {
        ProgressionDecision(weight: 80.0, reps: 10, deltaApplied: 0, rationale: .standardProgression)
    }

    func restMultiplier(history: [ExerciseHistory]) -> Double {
        1.0
    }

    func detectPersonalRecord(
        exercise: Exercise,
        weight: Double,
        reps: Int
    ) -> PersonalRecord? {
        nil
    }

    func generateWeekPlan(
        startDate: Date,
        recoveryScores: [Date: Double],
        footballDays: ActiveDays,
        split: TrainingSplit,
        customWeekdayMap: [WorkoutType]? = nil,
        recoveryThresholdOffset: Double = 0,
        matchDayKeys: Set<Date> = [],
        competitiveMatchDayKeys: Set<Date>? = nil,
        emphasis: BlockEmphasis = .physique,
        easyModalityPreference: [WorkoutType] = [.pool, .run],
        referenceDate: Date = Date()
    ) -> [WorkoutPlan] {
        (0 ..< 7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: startDate) ?? startDate
            let types: [WorkoutType] = [.push, .pull, .legs, .push, .pull, .football, .rest]
            return WorkoutPlan(
                date: date,
                type: types[offset],
                status: .planned
            )
        }
    }

    func isDeloadWeek(
        date: Date,
        deloadFrequencyWeeks: Int,
        trainingStartDate: Date?,
        fatigueEWMA: Double? = nil
    ) -> Bool {
        false
    }

    func deloadWeightMultiplier() -> Double {
        0.6
    }
}
