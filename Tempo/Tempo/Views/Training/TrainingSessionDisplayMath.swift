//
// TrainingSessionDisplayMath.swift
// Tempo
//
// Pure, unit-testable helpers pulled out of ActiveWorkoutView/WorkoutSummaryView
// so the display-only math around bodyweight lifts and PR labels doesn't live
// exclusively inside SwiftUI view bodies (the project has no view-testing
// harness, so anything worth pinning with a test has to be a plain function).
//

import Foundation

// MARK: - BodyweightLiftMath

/// §15 fix — a bodyweight-loaded lift (pull-up/dip) must never log 0 kg just
/// because the user has no profile bodyweight on file yet.
enum BodyweightLiftMath {
    /// Effective load (kg) for a bodyweight-loaded lift: the known profile
    /// bodyweight when there is one, otherwise the inline session prompt's
    /// value — either way, signed added load (belt/vest positive, assistance
    /// negative) is applied on top, and the result never goes below 0.
    static func effectiveLoadKg(
        profileBodyweightKg: Double,
        promptBodyweightKg: Double,
        addedLoadKg: Double
    ) -> Double {
        let base = profileBodyweightKg > 0 ? profileBodyweightKg : promptBodyweightKg
        return max(0, base + addedLoadKg)
    }
}

// MARK: - PRDisplay

/// Formatting for a `PersonalRecord` in the user's chosen weight unit.
/// `TrainingEngine.detectPersonalRecord`'s `context` string is kg-only and
/// unit-unaware ("82kg x 5 reps" even when the user reads in lbs) — these
/// helpers never render that embedded weight number, only `pr.value`
/// (always stored kg) converted properly, plus — best-effort — the rep
/// count parsed back out of `context` for a rep-max's subtitle. §15.
enum PRDisplay {
    /// Pulls just the rep count out of the engine's context string, e.g.
    /// "82kg x 5 reps" → "5". nil when the string doesn't match (no context,
    /// or a shape the engine hasn't produced yet).
    static func repsFromContext(_ context: String?) -> String? {
        guard let context, let match = context.firstMatch(of: /(\d+)\s*reps?/) else {
            return nil
        }
        return String(match.1)
    }

    /// `pr.value` (always kg) converted and formatted in `unit`.
    static func weightLabel(_ pr: PersonalRecord, unit: WeightUnit, decimals: Int = 1) -> String {
        let display = WeightUnit.kg.convert(pr.value, to: unit)
        return String(format: "%.\(decimals)f %@", display, unit.abbreviation)
    }

    /// Short subtitle for a PR row/toast — type-aware, unit-agnostic (never
    /// repeats a weight number the caller is already showing from
    /// `weightLabel`).
    static func subtitle(_ pr: PersonalRecord) -> String {
        switch pr.type {
        case .oneRepMax:
            "New estimated 1RM"
        case .repMax:
            if let reps = repsFromContext(pr.context) {
                "New \(reps)-rep max"
            } else {
                "New rep max"
            }
        case .volume:
            "New volume PR"
        }
    }
}
