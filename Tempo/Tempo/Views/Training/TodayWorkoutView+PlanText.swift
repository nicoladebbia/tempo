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
            return TideTrain.positive
        }
        if adj >= 0.6 {
            return TideTrain.caution
        }
        return Tide.danger
    }

    func recoveryText(plan: WorkoutPlan) -> String {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return String(localized: "Green Recovery")
        }
        if adj >= 0.6 {
            return String(localized: "Yellow Recovery")
        }
        return String(localized: "Red Recovery")
    }

    func adjustmentLabel(plan: WorkoutPlan) -> String {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return String(localized: "Full Volume")
        }
        if adj >= 0.8 {
            return String(localized: "-20% Volume")
        }
        if adj >= 0.75 {
            return String(localized: "-20% Volume, Lighter Load")
        }
        return String(localized: "Swapped to Mobility")
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

        let isBodyweightLift = leadSet.plannedExercise?.exercise
            .map { StrengthStandards.isBodyweightLoaded($0.equipment) } ?? false

        var text: String
        if isBodyweightLift, !leadSet.isCalibration {
            // Pull-up/dip: show bodyweight ± added load, never the effective
            // load as if it were a plate weight ("Pull-Up @ 7kg").
            text = "\(setCount) x \(reps) \(Self.bodyweightLoadText(addedKg: leadSet.addedLoadKg, unit: unit))"
        } else if let weight = leadSet.targetWeight, weight > 0 {
            let displayWeight = WeightUnit.kg.convert(weight, to: unit)
            text = "\(setCount) x \(reps) @ \(Self.weightText(displayWeight))\(unit.abbreviation)"
        } else if leadSet.isCalibration {
            // §5 — a trainer % with no reliable max: no weight to show yet,
            // the first set calibrates it live.
            text = String(localized: "\(setCount) x \(reps) · calibrate first set")
        } else {
            text = String(localized: "\(setCount) x \(reps) (BW)")
        }

        // §11.12 — effort target rides the prescription line when the
        // e1RM-anchored path set one.
        if let rir = leadSet.targetRIR, !leadSet.isCalibration {
            text += " · \(String(localized: "RIR \(rir)"))"
        }

        if !warmupSets.isEmpty {
            // §13 — every warmup on a trainer day is one Tempo added; the
            // trainer never wrote it.
            let warmupCount = warmupSets.count
            text += " + " + (isTrainerDay ? String(localized: "\(warmupCount) Tempo warm-up") : String(localized: "\(warmupCount) warmup"))
        }

        return text
    }

    /// "(BW)", "@ BW +10kg", or "@ BW −15kg assist" for a bodyweight-loaded lift.
    static func bodyweightLoadText(addedKg: Double?, unit: WeightUnit) -> String {
        guard let addedKg, abs(addedKg) >= 0.5 else {
            return String(localized: "(BW)")
        }
        let display = weightText(abs(WeightUnit.kg.convert(addedKg, to: unit)))
        return addedKg > 0
            ? String(localized: "@ BW +\(display)\(unit.abbreviation)")
            : String(localized: "@ BW −\(display)\(unit.abbreviation) assist")
    }

    /// 22.5 stays "22.5" (Int() used to truncate it to "22"); whole numbers drop the decimal.
    static func weightText(_ value: Double) -> String {
        WeightFormat.number(value)
    }
}
