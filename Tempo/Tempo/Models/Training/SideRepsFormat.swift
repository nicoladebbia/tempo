//
// SideRepsFormat.swift
// Tempo
//
// Fix #9 — shared copy for unilateral (per-side) trainer prescriptions
// (`PlannedExercise.perSide`), so the Today card, the active workout set
// row, the workout summary and history all render the same "N / side"
// label instead of each view inventing its own suffix.
//
// Naming note: `ActiveWorkoutView` already uses "per side" for a DIFFERENT
// concept — plates per side of a loaded barbell (`perSideHint`, `PlateMath`).
// This type is about REPS worked one side of the BODY at a time; callers
// near that plate-math code should keep the two visually distinct (see
// `SideRepsFormat.load`, which reads "/ hand" rather than "/ side" for
// exactly this reason).
//

import Foundation

enum SideRepsFormat {
    /// "8" → "8", or "8 / side" for a per-side prescription/target.
    static func reps(_ reps: Int, perSide: Bool) -> String {
        guard perSide else {
            return "\(reps)"
        }
        return "\(reps) / side"
    }

    /// A LOGGED set's reps: the plain count, "N / side" when both sides
    /// matched, or "L n / R n" when the athlete logged an uneven split
    /// (`PlannedSet.actualRepsLeft`/`actualRepsRight`).
    static func loggedReps(actual: Int, left: Int?, right: Int?, perSide: Bool) -> String {
        guard perSide else {
            return "\(actual)"
        }
        if let left, let right, left != right {
            return "L \(left) / R \(right)"
        }
        return "\(actual) / side"
    }

    /// A per-side dumbbell/kettlebell load reads as "20kg / hand" so it's
    /// never misread as the combined two-hand weight — barbell/machine
    /// per-side lifts (rare, but possible on a single-arm cable row) keep
    /// the plain weight text since there's no "hand" to attribute it to.
    static func load(_ text: String, perSide: Bool, equipment: Equipment) -> String {
        guard perSide, equipment == .dumbbell || equipment == .kettlebell else {
            return text
        }
        return "\(text) / hand"
    }
}
