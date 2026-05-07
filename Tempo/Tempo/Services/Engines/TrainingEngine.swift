//
// TrainingEngine.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - Training Engine (Real Implementation)

// Per MODULE_TRAINING.md Sections 15-19 — Workout generation, progressive overload,
// recovery adjustment, football integration, deload detection.

final class TrainingEngine: TrainingEngineProtocol, @unchecked Sendable {
    // MARK: - Constants

    // Per MODULE_TRAINING.md Section 16.2 — Standard weight increments

    private static let barbellIncrement: Double = 2.5
    private static let dumbbellIncrement: Double = 2.0
    private static let cableIncrement: Double = 2.5
    private static let defaultIncrement: Double = 2.5
    private static let deloadWeekInterval: Int = 5 // weeks

    // MARK: - Generate Workout

    // Per MODULE_TRAINING.md Section 15 — Full workout generation for a single day.

    func generateWorkout(
        for date: Date,
        recoveryScore: Double?,
        footballDays: ActiveDays,
        split: TrainingSplit
    ) -> WorkoutPlan {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)

        // Per MODULE_TRAINING.md Section 18 — Check football constraints
        let isFootballDay = footballDays.isActive(on: weekday)
        let isTMinus1 = isFootballTMinus1(date: date, footballDays: footballDays)
        let isTPlus1 = isFootballTPlus1(date: date, footballDays: footballDays)

        // Per MODULE_TRAINING.md Section 18.2 — T-0: locked to football
        if isFootballDay {
            return WorkoutPlan(
                date: date,
                type: .football,
                notes: "Match day — pre-match prep only"
            )
        }

        // Determine recovery zone
        let zone = classifyRecoveryZone(score: recoveryScore)

        // Per MODULE_TRAINING.md Section 17.2 — Red: mobility or rest
        if zone == .red {
            return WorkoutPlan(
                date: date,
                type: .mobility,
                recoveryAdjustment: 0.0,
                notes: "Recovery is low — 25-min mobility session"
            )
        }

        // Per MODULE_TRAINING.md Section 18.2 — T+1: recovery-dependent, no legs
        if isTPlus1 {
            if zone == .red {
                return WorkoutPlan(date: date, type: .rest, notes: "Rest after yesterday's match")
            }
            // Upper body only on T+1, even with green recovery
            let upperType = preferredUpperType(for: date, split: split)
            let adjustment = zone == .yellow ? 0.8 : 1.0
            return WorkoutPlan(
                date: date,
                type: upperType,
                recoveryAdjustment: adjustment,
                notes: "Upper body only — T+1 after football"
            )
        }

        // Determine workout type from split rotation
        var workoutType = nextWorkoutType(for: date, split: split)

        // Per MODULE_TRAINING.md Section 18.2 — T-1: no legs
        if isTMinus1, workoutType == .legs {
            workoutType = swapLegsForUpper(split: split)
        }

        // Apply recovery adjustment
        // Per MODULE_TRAINING.md Section 17.2
        let recoveryAdjustment: Double
        switch zone {
        case .green:
            recoveryAdjustment = 1.0
        case .yellow:
            let score = recoveryScore ?? 50
            if score >= 50 {
                // Upper yellow: -20% volume only
                recoveryAdjustment = 0.8
            } else {
                // Lower yellow: -20% volume, -5% weight
                recoveryAdjustment = 0.75
            }
        case .red:
            recoveryAdjustment = 0.6 // shouldn't reach here, handled above
        }

        return WorkoutPlan(
            date: date,
            type: workoutType,
            recoveryAdjustment: recoveryAdjustment,
            notes: zone == .yellow ? "Recovery-adjusted workout" : nil
        )
    }

    // MARK: - Adjust For Recovery

    // Per MODULE_TRAINING.md Section 17.2 — Apply volume/intensity adjustments

    func adjustForRecovery(plan: WorkoutPlan, score: Double) -> WorkoutPlan {
        let zone = classifyRecoveryZone(score: score)

        switch zone {
        case .red:
            plan.type = .mobility
            plan.recoveryAdjustment = 0.0
            plan.notes = "Recovery is low — mobility session instead"
        case .yellow:
            if score >= 50 {
                plan.recoveryAdjustment = 0.8
            } else {
                plan.recoveryAdjustment = 0.75
            }
            plan.notes = "Recovery-adjusted: reduced volume"
        case .green:
            plan.recoveryAdjustment = 1.0
        }

        return plan
    }

    // MARK: - Progressive Overload

    // Per MODULE_TRAINING.md Section 16 — 2-of-3 rule

    func calculateProgressiveOverload(
        for exercise: Exercise,
        history: [ExerciseHistory]
    ) -> (weight: Double, reps: Int) {
        let defaultReps = exercise.isCompound ? 8 : 12
        let increment = weightIncrement(for: exercise.equipment)

        // Need at least 2 sessions of data
        let recentSessions = history.sorted { $0.date > $1.date }.prefix(3)
        guard recentSessions.count >= 2 else {
            // Not enough data — keep current or use last known weight
            let lastWeight = history.first?.bestSetWeight ?? 0
            return (weight: lastWeight, reps: defaultReps)
        }

        let currentWeight = recentSessions.first?.bestSetWeight ?? 0

        // Per MODULE_TRAINING.md Section 16.1 — Count successful sessions
        // A session is successful if best set hit target reps at target weight
        var successCount = 0
        for session in recentSessions {
            if let bestReps = session.bestSetReps, bestReps >= defaultReps {
                successCount += 1
            }
        }

        // Per MODULE_TRAINING.md Section 16.1 — Decision
        if successCount >= 2 {
            // Increase weight
            return (weight: currentWeight + increment, reps: defaultReps)
        } else if successCount == 0, recentSessions.count >= 3 {
            // Failed 3 sessions in a row — check if needs deload
            let avgReps = recentSessions.compactMap(\.bestSetReps)
                .reduce(0, +) / max(1, recentSessions.count)
            if avgReps < Int(Double(defaultReps) * 0.75) {
                // Decrease weight
                return (weight: max(0, currentWeight - increment), reps: defaultReps)
            }
        }

        // Keep current weight
        return (weight: currentWeight, reps: defaultReps)
    }

    // MARK: - PR Detection

    // Per MODULE_TRAINING.md Section 12 — Compare to historical bests

    func detectPersonalRecord(
        exercise: Exercise,
        weight: Double,
        reps: Int
    ) -> PersonalRecord? {
        guard weight > 0, reps > 0 else {
            return nil
        }

        // Calculate estimated 1RM using Brzycki formula
        let estimated1RM: Double = if reps == 1 {
            weight
        } else {
            weight * (36.0 / (37.0 - Double(reps)))
        }

        // Compare to all-time PR
        let currentPR = exercise.allTimePR ?? 0
        if estimated1RM > currentPR {
            return PersonalRecord(
                type: .oneRepMax,
                value: estimated1RM,
                date: Date(),
                context: "\(Int(weight))kg x \(reps) reps",
                exercise: exercise
            )
        }

        // Check rep max PR — highest weight at this rep count or above
        let records = exercise.personalRecords ?? []
        let repMaxPR = records
            .filter { $0.type == .repMax }
            .max { $0.value < $1.value }
        if weight > (repMaxPR?.value ?? 0), reps >= 3 {
            return PersonalRecord(
                type: .repMax,
                value: weight,
                date: Date(),
                context: "\(Int(weight))kg x \(reps) reps",
                exercise: exercise
            )
        }

        return nil
    }

    // MARK: - Generate Week Plan

    // Per MODULE_TRAINING.md Section 15.4 — Full week planning with football awareness

    func generateWeekPlan(
        startDate: Date,
        recoveryScore: Double?,
        footballDays: ActiveDays,
        split: TrainingSplit
    ) -> [WorkoutPlan] {
        let cal = Calendar.current
        var plans: [WorkoutPlan] = []
        var splitIndex = 0

        // Per MODULE_TRAINING.md Section 15.4 — Phase 1: Assign workout types to days
        let splitSequence = getSplitSequence(split)
        let trainingDaysNeeded = splitSequence.count

        // First pass: identify football days, T-1, T+1
        var dayMeta: [(date: Date, isFootball: Bool, isTMinus1: Bool, isTPlus1: Bool)] = []
        for offset in 0 ..< 7 {
            let date = cal.date(byAdding: .day, value: offset, to: startDate)!
            let weekday = cal.component(.weekday, from: date)
            dayMeta.append((
                date: date,
                isFootball: footballDays.isActive(on: weekday),
                isTMinus1: isFootballTMinus1(date: date, footballDays: footballDays),
                isTPlus1: isFootballTPlus1(date: date, footballDays: footballDays)
            ))
        }

        // Assign types
        for meta in dayMeta {
            // Per MODULE_TRAINING.md Section 18.2 — T-0
            if meta.isFootball {
                plans.append(WorkoutPlan(
                    date: meta.date,
                    type: .football,
                    notes: "Match day"
                ))
                continue
            }

            let zone = classifyRecoveryZone(score: recoveryScore)

            // Per MODULE_TRAINING.md Section 18.2 — T+1
            if meta.isTPlus1 {
                switch zone {
                case .red:
                    plans.append(WorkoutPlan(
                        date: meta.date,
                        type: .rest,
                        notes: "Rest — T+1 after football"
                    ))
                case .yellow:
                    let score = recoveryScore ?? 50
                    if score < 50 {
                        plans.append(WorkoutPlan(
                            date: meta.date,
                            type: .mobility,
                            notes: "Mobility — T+1 after football"
                        ))
                    } else {
                        let upperType = preferredUpperType(for: meta.date, split: split)
                        plans.append(WorkoutPlan(
                            date: meta.date,
                            type: upperType,
                            recoveryAdjustment: 0.8,
                            notes: "Reduced upper body — T+1"
                        ))
                        splitIndex += 1
                    }
                case .green:
                    // Upper body only even with green (neuromuscular impairment)
                    let upperType = preferredUpperType(for: meta.date, split: split)
                    plans.append(WorkoutPlan(
                        date: meta.date,
                        type: upperType,
                        notes: "Upper body only — T+1 after football"
                    ))
                    splitIndex += 1
                }
                continue
            }

            // Red recovery → mobility
            if zone == .red {
                plans.append(WorkoutPlan(
                    date: meta.date,
                    type: .mobility,
                    recoveryAdjustment: 0.0,
                    notes: "Recovery is low"
                ))
                continue
            }

            // Normal training day
            if splitIndex < trainingDaysNeeded {
                var workoutType = splitSequence[splitIndex]

                // Per MODULE_TRAINING.md Section 18.2 — T-1: no legs
                if meta.isTMinus1 && workoutType == .legs {
                    workoutType = swapLegsForUpper(split: split)
                }

                let adjustment: Double = zone == .yellow
                    ? ((recoveryScore ?? 50) >= 50 ? 0.8 : 0.75)
                    : 1.0

                plans.append(WorkoutPlan(
                    date: meta.date,
                    type: workoutType,
                    recoveryAdjustment: adjustment,
                    notes: zone == .yellow ? "Recovery-adjusted" : nil
                ))
                splitIndex += 1
            } else {
                // Extra days → rest (prefer Sunday)
                let weekday = cal.component(.weekday, from: meta.date)
                if weekday == 1 { // Sunday
                    plans.append(WorkoutPlan(date: meta.date, type: .rest))
                } else if zone == .green {
                    plans.append(WorkoutPlan(
                        date: meta.date,
                        type: .mobility,
                        notes: "Active recovery"
                    ))
                } else {
                    plans.append(WorkoutPlan(date: meta.date, type: .rest))
                }
            }
        }

        return plans
    }

    // MARK: - Calendar-Aware Week Plan

    // Per BUILD_PLAN step 13.2 — Merge calendar-detected football days with static settings.
    // Football on calendar → training plan avoids heavy legs the day before.

    func generateWeekPlan(
        startDate: Date,
        recoveryScore: Double?,
        footballDays: ActiveDays,
        calendarFootballDates: [Date],
        split: TrainingSplit
    ) -> [WorkoutPlan] {
        // Merge static footballDays bitmask with calendar-detected dates
        let cal = Calendar.current
        var mergedFootballDays = footballDays

        for footballDate in calendarFootballDates {
            let weekday = cal.component(.weekday, from: footballDate)
            mergedFootballDays = ActiveDays(rawValue: mergedFootballDays.rawValue | (1 << weekday))
        }

        return generateWeekPlan(
            startDate: startDate,
            recoveryScore: recoveryScore,
            footballDays: mergedFootballDays,
            split: split
        )
    }

    // MARK: - Deload Detection

    // Every Nth week (configurable), generate a deload week.
    // Deload: reduce weights by 40%, keep reps the same.

    func isDeloadWeek(date: Date, deloadFrequencyWeeks: Int, trainingStartDate: Date?) -> Bool {
        let cal = Calendar.current
        let startDate = trainingStartDate ?? cal.date(byAdding: .month, value: -3, to: date) ?? date
        let weeksSinceStart = cal.dateComponents([.weekOfYear], from: cal.startOfDay(for: startDate), to: cal.startOfDay(for: date))
            .weekOfYear ?? 0
        let frequency = max(1, deloadFrequencyWeeks)
        // Week N, 2N, 3N... are deload weeks (1-indexed: weeks frequency, 2*frequency, etc.)
        return weeksSinceStart > 0 && (weeksSinceStart % frequency) == 0
    }

    func deloadWeightMultiplier() -> Double {
        0.6 // 40% reduction
    }

    // MARK: - Private Helpers

    // Recovery zone classification
    // Per CROSS_DOC_AUDIT.md canonical boundaries: Green >= 67, Yellow 34-66, Red < 34

    private func classifyRecoveryZone(score: Double?) -> RecoveryZone {
        guard let score else {
            return .green
        } // default to green if no data
        if score >= 67 {
            return .green
        }
        if score >= 34 {
            return .yellow
        }
        return .red
    }

    // Per MODULE_TRAINING.md Section 16.2 — Weight increment by equipment

    private func weightIncrement(for equipment: Equipment) -> Double {
        switch equipment {
        case .barbell: Self.barbellIncrement
        case .dumbbell: Self.dumbbellIncrement
        case .cable,
             .machine: Self.cableIncrement
        default: Self.defaultIncrement
        }
    }

    // Get the ordered split sequence for a training split
    // Per MODULE_TRAINING.md Section 15.4

    private func getSplitSequence(_ split: TrainingSplit) -> [WorkoutType] {
        switch split {
        case .pushPullLegs:
            [.push, .pull, .legs, .push, .pull, .legs]
        case .upperLower:
            [.upper, .lower, .upper, .lower]
        case .fullBody:
            [.fullBody, .fullBody, .fullBody]
        case .bro:
            [.push, .pull, .legs, .push, .pull]
        case .custom:
            [.push, .pull, .legs] // fallback
        }
    }

    // Determine next workout type for a given date based on split rotation
    // Uses day-of-week for deterministic rotation

    private func nextWorkoutType(for date: Date, split: TrainingSplit) -> WorkoutType {
        let cal = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) ?? 0
        let sequence = getSplitSequence(split)
        guard !sequence.isEmpty else {
            return .push
        }
        return sequence[dayOfYear % sequence.count]
    }

    // Swap legs for an upper body type based on split
    // Per MODULE_TRAINING.md Section 18.2 — T-1 swap

    private func swapLegsForUpper(split: TrainingSplit) -> WorkoutType {
        switch split {
        case .pushPullLegs,
             .bro,
             .custom:
            .push
        case .upperLower:
            .upper
        case .fullBody:
            .upper
        }
    }

    // Get preferred upper body type for T+1 days
    // Per MODULE_TRAINING.md Section 18.2 — Prefer Pull on T+1

    private func preferredUpperType(for date: Date, split: TrainingSplit) -> WorkoutType {
        switch split {
        case .pushPullLegs,
             .bro,
             .custom:
            .pull // Per Section 18.2: prefer Pull on T+1
        case .upperLower,
             .fullBody:
            .upper
        }
    }

    // Check if date is T-1 (day before a football day)
    // Per MODULE_TRAINING.md Section 18.2

    private func isFootballTMinus1(date: Date, footballDays: ActiveDays) -> Bool {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: date) else {
            return false
        }
        let tomorrowWeekday = cal.component(.weekday, from: tomorrow)
        return footballDays.isActive(on: tomorrowWeekday)
    }

    // Check if date is T+1 (day after a football day)
    // Per MODULE_TRAINING.md Section 18.2

    private func isFootballTPlus1(date: Date, footballDays: ActiveDays) -> Bool {
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: date) else {
            return false
        }
        let yesterdayWeekday = cal.component(.weekday, from: yesterday)
        return footballDays.isActive(on: yesterdayWeekday)
    }
}
