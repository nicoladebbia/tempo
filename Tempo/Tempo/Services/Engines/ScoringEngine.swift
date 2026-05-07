//
// ScoringEngine.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - Scoring Engine (Real Implementation)

// Per BUILD_PLAN step 10.7.
// Per ARCHITECTURE.md — Daily Score composite.
// Per MODULE_ARENA.md — XP System scoring.

final class ScoringEngine: ScoringEngineProtocol, @unchecked Sendable {
    // MARK: - Weight Configuration

    // Per BUILD_PLAN 10.7 — weighted composite:
    //   Non-negotiable completion: 40%
    //   Training compliance: 20%
    //   Nutrition compliance: 20%
    //   Recovery compliance: 10%
    //   Steps/activity: 10%

    private let weightNonNeg: Double = 0.40
    private let weightTraining: Double = 0.20
    private let weightNutrition: Double = 0.20
    private let weightRecovery: Double = 0.10
    private let weightActivity: Double = 0.10

    // MARK: - Daily Score

    func calculateDailyScore(
        snapshot: DailySnapshot,
        accountability: DailyAccountability
    ) -> Int {
        let breakdown = detailedBreakdown(snapshot: snapshot, accountability: accountability)
        let total = breakdown.nonNegotiableScore * weightNonNeg
            + breakdown.trainingScore * weightTraining
            + breakdown.nutritionScore * weightNutrition
            + breakdown.recoveryScore * weightRecovery
            + breakdown.activityScore * weightActivity

        return min(100, max(0, Int(total)))
    }

    // MARK: - Score Breakdown (Protocol)

    func scoreBreakdown(snapshot: DailySnapshot) -> ScoreBreakdown {
        // Body: recovery score (Whoop) + sleep score
        let body = bodyScore(snapshot: snapshot)

        // Fuel: calorie + macro compliance
        let fuel = fuelScore(snapshot: snapshot)

        // Mind: study compliance
        let mind = mindScore(snapshot: snapshot)

        // Move: training + steps
        let move = moveScore(snapshot: snapshot)

        return ScoreBreakdown(body: body, fuel: fuel, mind: mind, move: move)
    }

    // MARK: - Detailed Breakdown

    struct DetailedBreakdown {
        let nonNegotiableScore: Double // 0-100
        let trainingScore: Double // 0-100
        let nutritionScore: Double // 0-100
        let recoveryScore: Double // 0-100
        let activityScore: Double // 0-100
    }

    func detailedBreakdown(
        snapshot: DailySnapshot,
        accountability: DailyAccountability
    ) -> DetailedBreakdown {
        DetailedBreakdown(
            nonNegotiableScore: nonNegotiableScore(accountability: accountability),
            trainingScore: trainingScore(snapshot: snapshot),
            nutritionScore: nutritionScore(snapshot: snapshot),
            recoveryScore: recoveryScore(snapshot: snapshot),
            activityScore: activityScore(snapshot: snapshot)
        )
    }

    // MARK: - Component Scores

    /// Non-negotiable completion score (0-100).
    /// Based on completion percentage + time bonus + no-skip bonus.
    private func nonNegotiableScore(accountability: DailyAccountability) -> Double {
        guard accountability.totalCount > 0 else {
            return 0
        }

        // Base: completion percentage × 80
        let base = accountability.completionPercentage * 80

        // Time bonus: completed before PS5 time = up to 10 points
        var timeBonus: Double = 0
        if accountability.allComplete, let unlockedAt = accountability.unlockedAt {
            let hour = Calendar.current.component(.hour, from: unlockedAt)
            if hour < 12 {
                timeBonus = 10 // Early bird
            } else if hour < 17 {
                timeBonus = 5 // Afternoon
            }
        }

        // No-skip bonus: all completed (not skipped) = 10 points
        let noSkipBonus: Double = accountability.allComplete ? 10 : 0

        return min(100, base + timeBonus + noSkipBonus)
    }

    /// Training compliance score (0-100).
    private func trainingScore(snapshot: DailySnapshot) -> Double {
        if snapshot.workoutCompleted {
            return 100
        }
        // Partial credit: high strain without explicit workout
        if let strain = snapshot.strain, strain > 10 {
            return 60
        }
        return 0
    }

    /// Nutrition compliance score (0-100).
    private func nutritionScore(snapshot: DailySnapshot) -> Double {
        var score: Double = 0

        // Meal logging: 40 points for all meals logged
        if snapshot.mealsPlanned > 0 {
            let mealRatio = Double(snapshot.mealsLogged) / Double(snapshot.mealsPlanned)
            score += min(40, mealRatio * 40)
        }

        // Calorie compliance: 30 points for being within 10% of target
        if let compliance = snapshot.calorieCompliance {
            let deviation = abs(1.0 - compliance)
            if deviation <= 0.10 {
                score += 30
            } else if deviation <= 0.20 {
                score += 20
            } else if deviation <= 0.30 {
                score += 10
            }
        }

        // Protein compliance: 30 points
        if let compliance = snapshot.proteinCompliance {
            if compliance >= 0.9 {
                score += 30
            } else if compliance >= 0.7 {
                score += 20
            } else if compliance >= 0.5 {
                score += 10
            }
        }

        return min(100, score)
    }

    /// Recovery compliance score (0-100).
    /// Based on sleep quality and recovery score.
    private func recoveryScore(snapshot: DailySnapshot) -> Double {
        var score: Double = 0

        // Sleep score: up to 50 points
        if let sleepScore = snapshot.sleepScore {
            score += sleepScore * 50
        }

        // Recovery score: up to 50 points
        if let recovery = snapshot.recoveryScore {
            score += (recovery / 100) * 50
        }

        return min(100, score)
    }

    /// Activity score (0-100).
    /// Based on steps and active calories.
    private func activityScore(snapshot: DailySnapshot) -> Double {
        var score: Double = 0

        // Steps: 8000 steps = 60 points, 10000 = 80 points, 12000+ = 100 points
        if let steps = snapshot.steps {
            if steps >= 12000 {
                score += 70
            } else if steps >= 10000 {
                score += 55
            } else if steps >= 8000 {
                score += 40
            } else if steps >= 5000 {
                score += 25
            } else if steps >= 3000 {
                score += 10
            }
        }

        // Active calories: up to 30 points
        if let cal = snapshot.activeCalories {
            if cal >= 500 {
                score += 30
            } else if cal >= 300 {
                score += 20
            } else if cal >= 150 {
                score += 10
            }
        }

        return min(100, score)
    }

    // MARK: - Quadrant Scores (for ScoreBreakdown)

    private func bodyScore(snapshot: DailySnapshot) -> Int {
        var score: Double = 0

        // Recovery: 40%
        if let recovery = snapshot.recoveryScore {
            score += (recovery / 100) * 40
        }

        // Sleep: 40%
        if let sleepScore = snapshot.sleepScore {
            score += sleepScore * 40
        }

        // HRV/RHR within healthy range: 20%
        if snapshot.hrv != nil {
            score += 10 // Has data bonus
        }
        if snapshot.rhr != nil {
            score += 10 // Has data bonus
        }

        return min(25, Int(score / 4)) // Each quadrant is 0-25
    }

    private func fuelScore(snapshot: DailySnapshot) -> Int {
        let nutrition = nutritionScore(snapshot: snapshot)
        return min(25, Int(nutrition / 4))
    }

    private func mindScore(snapshot: DailySnapshot) -> Int {
        guard snapshot.studyTarget > 0 else {
            return 0
        }
        let compliance = Double(snapshot.studyMinutes) / Double(snapshot.studyTarget)
        return min(25, Int(compliance * 25))
    }

    private func moveScore(snapshot: DailySnapshot) -> Int {
        var score: Double = 0
        if snapshot.workoutCompleted {
            score += 50
        }
        if let steps = snapshot.steps, steps >= 8000 {
            score += 30
        }
        if let cal = snapshot.activeCalories, cal >= 300 {
            score += 20
        }
        return min(25, Int(score / 4))
    }
}
