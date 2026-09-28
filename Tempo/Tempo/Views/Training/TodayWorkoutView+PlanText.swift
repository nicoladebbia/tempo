//
// TodayWorkoutView+PlanText.swift
// Tempo
//
// Recovery/adjustment labels, duration estimate and prescription text for
// Today's cards — split out of TodayWorkoutView.swift to keep it under the
// SwiftLint type-body length cap.
//

import SwiftUI

extension TodayWorkoutView {
    func recoveryDotColor(plan: WorkoutPlan) -> Color {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return Color.tempoRecoveryGreen
        }
        if adj >= 0.6 {
            return Color.tempoRecoveryYellow
        }
        return Color.tempoRecoveryRed
    }

    func recoveryText(plan: WorkoutPlan) -> String {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return "Green Recovery"
        }
        if adj >= 0.6 {
            return "Yellow Recovery"
        }
        return "Red Recovery"
    }

    func adjustmentLabel(plan: WorkoutPlan) -> String {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return "Full Volume"
        }
        if adj >= 0.8 {
            return "-20% Volume"
        }
        if adj >= 0.75 {
            return "-20% Volume, Lighter Load"
        }
        return "Swapped to Mobility"
    }

    func estimatedDuration(plan: WorkoutPlan) -> Int {
        let exercises = plan.orderedExercises
        guard !exercises.isEmpty else {
            return 20
        }

        var totalMinutes = 5.0 // Warmup period
        let exerciseCount = exercises.count

        for (index, plannedEx) in exercises.enumerated() {
            let sets = plannedEx.orderedSets
            let isCompound = plannedEx.exercise?.isCompound ?? false

            for set in sets {
                if set.isWarmup {
                    totalMinutes += 1.0 // Warmup sets: 1 min each
                } else if isCompound {
                    totalMinutes += 2.5 // Working compound sets: 2.5 min (set + rest)
                } else {
                    totalMinutes += 1.5 // Working isolation sets: 1.5 min (set + rest)
                }
            }

            // Between-exercise transition (not after the last exercise)
            if index < exerciseCount - 1 {
                totalMinutes += 1.0
            }
        }

        totalMinutes += 3.0 // Cooldown

        return max(20, Int(totalMinutes.rounded()))
    }

    func prescriptionText(sets: [PlannedSet], firstSet: PlannedSet, isTrainerDay: Bool = false, perSide: Bool = false) -> String {
        let workingSets = sets.filter { !$0.isWarmup }
        let warmupSets = sets.filter(\.isWarmup)
        let setCount = workingSets.count
        let leadSet = workingSets.first ?? firstSet
        // Fix #9 — "8" vs "8 / side" for a unilateral trainer prescription.
        let reps = SideRepsFormat.reps(leadSet.targetReps, perSide: perSide)
        let unit = settings?.weightUnit ?? .kg

        var text: String
        if let weight = leadSet.targetWeight, weight > 0 {
            let displayWeight = WeightUnit.kg.convert(weight, to: unit)
            text = "\(setCount) x \(reps) @ \(Int(displayWeight))\(unit.abbreviation)"
        } else if leadSet.isCalibration {
            // §5 — a trainer % with no reliable max: no weight to show yet,
            // the first set calibrates it live.
            text = "\(setCount) x \(reps) · calibrate first set"
        } else {
            text = "\(setCount) x \(reps) (BW)"
        }

        // §11.12 — effort target rides the prescription line when the
        // e1RM-anchored path set one.
        if let rir = leadSet.targetRIR, !leadSet.isCalibration {
            text += " · RIR \(rir)"
        }

        if !warmupSets.isEmpty {
            // §13 — every warmup on a trainer day is one Tempo added; the
            // trainer never wrote it.
            text += " + \(warmupSets.count) \(isTrainerDay ? "Tempo warm-up" : "warmup")"
        }

        return text
    }
}
