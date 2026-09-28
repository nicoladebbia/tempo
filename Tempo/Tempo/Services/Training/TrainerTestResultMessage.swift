//
// TrainerTestResultMessage.swift
// Tempo
//
// trainer-feedback-tests — "tell the athlete what changed" copy for a logged
// TEST result: a strength test's new max, or a run test's new timed
// baseline. Pure formatting only (no I/O, no SwiftData writes) — the actual
// trusted-max/baseline bookkeeping lives in `TrainingViewModel.
// persistCompletion` (strength) and `TrainingViewModel.logConditioningBlock`
// (conditioning); this just turns the result into a sentence.
//

import Foundation

enum TrainerTestResultMessage {
    // MARK: - Strength test

    /// "New max: Squat 120 kg — your trainer's 75% is now 90 kg." Looks up
    /// the FIRST %1RM the trainer wrote anywhere in `program` for this exact
    /// exercise (by `exerciseID`) to make the "now X" half concrete; falls
    /// back to a plain "New max: Squat 120 kg." when `program` has no
    /// %-based prescription for it (or is nil — e.g. the program has since
    /// been deleted).
    static func strengthTestMessage(
        exercise: Exercise,
        newMaxKg: Double,
        weightUnit: WeightUnit,
        program: TrainerProgram?
    ) -> String? {
        guard newMaxKg > 0 else {
            return nil
        }
        let base = "New max: \(exercise.name) \(formattedWeight(newMaxKg, unit: weightUnit))"
        guard let program, let percent = firstPercent(for: exercise, in: program) else {
            return "\(base)."
        }
        let percentLabel = "\(Int((percent * 100).rounded()))%"
        let loadDisplay = formattedWeight(newMaxKg * percent, unit: weightUnit)
        return "\(base) — your trainer's \(percentLabel) is now \(loadDisplay)."
    }

    /// The first %1RM the trainer wrote anywhere in the program for this
    /// exercise (by `exerciseID`), in program/week/day order. A trainer
    /// program rarely varies the % for the same lift week to week, so
    /// "first found" is a representative choice, not an arbitrary one.
    private static func firstPercent(for exercise: Exercise, in program: TrainerProgram) -> Double? {
        for week in program.weeks {
            for day in week.days {
                for item in day.exercises where item.exerciseID == exercise.id {
                    if let percent = item.percentOf1RM, percent > 0 {
                        return percent
                    }
                }
            }
        }
        return nil
    }

    private static func formattedWeight(_ kg: Double, unit: WeightUnit) -> String {
        let converted = WeightUnit.kg.convert(kg, to: unit)
        let rounded = (converted * 10).rounded() / 10
        let numberText = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
        return "\(numberText) \(unit.abbreviation)"
    }

    // MARK: - Run/time-trial test

    /// "New best: 30m in 4.30″" — a run/sprint test's timed baseline.
    static func runTestMessage(label: String, seconds: Double) -> String {
        "New best: \(label) in \(ConditioningBaselineProvider.formattedSeconds(seconds))"
    }
}
