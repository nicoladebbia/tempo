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
        split: TrainingSplit
    ) -> WorkoutPlan {
        WorkoutPlan(
            date: date,
            type: .push,
            status: .planned,
            notes: "Mock push workout"
        )
    }

    func adjustForRecovery(plan: WorkoutPlan, score: Double) -> WorkoutPlan {
        plan
    }

    func calculateProgressiveOverload(
        for exercise: Exercise,
        history: [ExerciseHistory]
    ) -> (weight: Double, reps: Int) {
        (weight: 80.0, reps: 10)
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
        split: TrainingSplit
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

    func isDeloadWeek(date: Date, deloadFrequencyWeeks: Int, trainingStartDate: Date?) -> Bool {
        false
    }

    func deloadWeightMultiplier() -> Double {
        0.6
    }
}
