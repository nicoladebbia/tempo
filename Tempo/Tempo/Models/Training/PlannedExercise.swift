//
// PlannedExercise.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - PlannedExercise

@Model
final class PlannedExercise {
    @Attribute(.unique)
    var id: UUID

    var order: Int

    var supersetGroup: Int?

    /// Trainer-program rest between sets (seconds). Wins over the exercise's
    /// own preference and the global default. Optional → lightweight migration.
    var restSecondsOverride: Int?

    /// The trainer's note for this exercise ("pause at the bottom").
    var programNote: String?

    /// §4 — the trainer's OWN target weight (kg) for this exercise, before
    /// Tempo's recovery/pain-note adjustments. Set only on a trainer-program
    /// exercise with a known number (explicit weight, or % of a reliable
    /// e1RM — see `TrainingViewModel.programWeightKg`); nil for generated
    /// days and for an effort-only % (no reliable max — see `PlannedSet.
    /// isCalibration`). Optional → lightweight SwiftData migration.
    var trainerTargetKg: Double?

    /// §4 — why today's prescribed weight differs from `trainerTargetKg`,
    /// e.g. "Recovery yellow −20%" or "Pain note — capped at last session".
    /// nil when Tempo didn't change the trainer's number. Optional →
    /// lightweight SwiftData migration.
    var loadAdjustmentNote: String?

    /// §4 — true once the athlete tapped "Use trainer's weight" to restore
    /// `trainerTargetKg` for this exercise's remaining sets today, overriding
    /// Tempo's automatic adjustment. Defaulted → SwiftData auto-migrates.
    var trainerOverrideApplied: Bool = false

    /// Fix #9 — true when every set is worked ONE SIDE AT A TIME (e.g. "SA DB
    /// Row 3x8 each", "SL RDL 3x6/side"): `PlannedSet.actualReps`/`targetReps`
    /// are the SINGLE-side rep count, and true tonnage covers both sides (see
    /// `PlannedSet.volume`). Set from `ProgramExercise.perSide` on import
    /// (`TrainingViewModel.populateFromTrainerProgram`); false for every
    /// generated/routine/CSV-imported slot — Tempo has no unilateral-only
    /// metadata on `Exercise` itself to infer it from otherwise. Defaulted →
    /// SwiftData auto-migrates.
    var perSide: Bool = false

    /// trainer-feedback-tests — true when this slot came from a `ProgramDay`/
    /// `ProgramExercise` flagged `isTest` (a 1RM/3RM/5RM/time-trial test day).
    /// Drives the "TEST — work up to a max" banner in the workout and, at
    /// workout completion, marks its `ExerciseHistory` row's e1RM as a
    /// TRUSTED max (`ExerciseHistory.isTrustedMax`) rather than an ordinary
    /// estimate — see `TrainingViewModel.reliableEstimated1RM`'s doc comment
    /// for how a trusted max outranks a same-or-later ordinary estimate. Set
    /// from `ProgramExercise.isTest`/`ProgramDay.isTest` on import
    /// (`TrainingViewModel.populateFromTrainerProgram`); false for every
    /// generated/routine slot. Defaulted → SwiftData auto-migrates.
    var isTestExercise: Bool = false

    /// Exercise name captured when this slot was created. `Exercise.
    /// plannedExercises` is `.nullify` (§10.6) — deleting a custom exercise
    /// detaches `exercise` instead of deleting this row, so a past session's
    /// slot must keep SOME name to show. nil while `exercise` is still set
    /// (read `exercise.name` — see `displayName`) or on legacy rows written
    /// before this field existed.
    var exerciseNameSnapshot: String?

    /// Pause/travel-pain feature — non-nil when `TravelSwapEngine` swapped
    /// this slot's exercise for a hotel/limited-equipment alternative, holding
    /// the trainer's ORIGINAL exercise name (for the "Hotel swap for Barbell
    /// RDL" label and the trainer-report "swapped (travel)" note — see
    /// `TrainerReportSupplementalSections.swift`). Set once, at population
    /// time, in `TrainingViewModel.populateFromTrainerProgram`. Optional →
    /// lightweight SwiftData migration.
    var travelSwapOriginalName: String?

    /// "This hurts" flow — true once the athlete (or the severe-pain flow)
    /// skipped this exercise for today due to pain. Display-only: doesn't
    /// touch `WorkoutPlan.totalSets`/`completedSets` (an unlogged set already
    /// reads honestly as not-done). Optional/defaulted → lightweight
    /// SwiftData migration.
    var painSkipped: Bool = false

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var workoutPlan: WorkoutPlan?

    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \PlannedSet.plannedExercise)
    var sets: [PlannedSet]?

    // MARK: - Computed

    /// The exercise's name — live if it still exists, else the snapshot taken
    /// at creation, else "Removed exercise" (deleted with no snapshot, e.g. a
    /// legacy row). Readers should use this instead of `exercise?.name`.
    ///
    /// Self-healing: while `exercise` is live, this also refreshes the
    /// snapshot to match it. A slot's `exercise` can be repointed after
    /// creation (an exercise SWAP, elsewhere), which the init-time capture
    /// alone wouldn't see — reading `displayName` even once after a swap
    /// (any session/history view does) re-syncs the snapshot before the new
    /// exercise could ever be deleted and need it.
    @Transient
    var displayName: String {
        if let name = exercise?.name {
            if exerciseNameSnapshot != name {
                exerciseNameSnapshot = name
            }
            return name
        }
        return exerciseNameSnapshot ?? "Removed exercise"
    }

    @Transient
    var orderedSets: [PlannedSet] {
        (sets ?? []).sorted { $0.setNumber < $1.setNumber }
    }

    @Transient
    var isComplete: Bool {
        guard let sets, !sets.isEmpty else {
            return false
        }
        // Completeness is gated by WORKING sets only. Warmup sets are guidance,
        // not work — an exercise whose working sets are all logged is done even
        // if a warmup set was skipped. (Fixes the missing checkmark on lifts
        // that carry warmup sets, e.g. Barbell Row.)
        let workingSets = sets.filter { !$0.isWarmup }
        guard !workingSets.isEmpty else {
            return sets.allSatisfy(\.completed)
        }
        return workingSets.allSatisfy(\.completed)
    }

    @Transient
    var bestSet: PlannedSet? {
        // Working sets only — a warmup ramp set must never be reported as the
        // "best" set of an exercise, and neither can a drop step (§6.4): it's
        // a reduced-weight backoff, never the max-effort signal "best" means.
        (sets ?? [])
            .filter { !$0.isWarmup && !$0.isDropStep && $0.completed && $0.actualWeight != nil }
            .max { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) }
    }

    @Transient
    var totalVolume: Double {
        // Working sets only — warmup ramp sets are not "volume". (Without this
        // filter, every compound after the first inflates its volume, since
        // its warmup sets flow through logSet as completed sets.)
        // Fix #9 — delegates to `PlannedSet.volume`, which already doubles a
        // per-side set's tonnage (or sums a logged L/R split) via this same
        // exercise's `perSide` flag, so this and `WorkoutPlan.totalVolume`
        // (which sums this property) can never drift out of sync with it.
        (sets ?? [])
            .filter { !$0.isWarmup }
            .reduce(0) { $0 + ($1.volume ?? 0) }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        order: Int,
        supersetGroup: Int? = nil,
        workoutPlan: WorkoutPlan? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.order = order
        self.supersetGroup = supersetGroup
        self.workoutPlan = workoutPlan
        self.exercise = exercise
        exerciseNameSnapshot = exercise?.name
    }
}

// MARK: - DTO

extension PlannedExercise {
    struct DTO: Codable {
        let id: UUID
        let order: Int
        let superset_group: Int?
        let exercise_id: UUID?
        let sets: [PlannedSet.DTO]?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            order: order,
            superset_group: supersetGroup,
            exercise_id: exercise?.id,
            sets: orderedSets.map { $0.toDTO() }
        )
    }
}
