//
// ExerciseHistory.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - ExerciseHistory

@Model
final class ExerciseHistory {
    @Attribute(.unique)
    var id: UUID

    var date: Date

    var estimated1RM: Double?

    var totalVolume: Double

    var bestSetWeight: Double?

    var bestSetReps: Int?

    var setsPerformed: Int?

    // MARK: - Feedback aggregates (Tier 2)

    // Aggregated from the session's SetFeedback rows, counting ONLY rows the
    // user actually filled in (userProvidedFeedback). All nullable/defaulted:
    // nil/0 means "no real feedback this session" → the engine progresses on
    // reps alone (legacy rows written before Tier 2 are also nil → same path).

    /// Mean RPE across entered working-set feedback this session (nil = none).
    var avgRPE: Double?

    /// Worst form quality across entered feedback (FormQuality.rawValue, nil = none).
    var worstFormRaw: String?

    /// How many ENTERED feedback rows fed the aggregates above.
    var feedbackSampleCount: Int = 0

    /// Fraction of entered feedback rows on this session marked `.gassed`
    /// (0...1). nil = no entered feedback this session. Read by
    /// `TrainingEngine.restMultiplier` to lengthen rest under conditioning
    /// debt. Additive + optional → lightweight SwiftData migration (matches the
    /// avgRPE/worstFormRaw fields above).
    var gassedFraction: Double?

    /// Scalar back-reference to the WorkoutPlan that produced this row. NOT a
    /// relationship — ExerciseHistory is the permanent training record and must
    /// outlive the ephemeral daily plan. The ID enables exact, idempotent dedup
    /// on save and exact cleanup on explicit workout deletion, without
    /// re-coupling the two lifecycles. Optional so it stays a lightweight
    /// SwiftData migration (nil on legacy rows written before this field).
    var workoutPlanID: UUID?

    /// Exercise name captured at write time. `Exercise.history` is `.nullify`
    /// (§10.6) — deleting a custom exercise detaches `exercise` here rather
    /// than deleting the row, so this permanent record needs its own name to
    /// keep showing once that happens. nil while `exercise` is still set
    /// (read `exercise.name` — see `displayName`) or on legacy rows.
    var exerciseNameSnapshot: String?

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    // MARK: - Computed

    /// The exercise's name — live if it still exists, else the snapshot taken
    /// at write time, else "Removed exercise". Readers should use this instead
    /// of `exercise?.name`. Self-healing: refreshes the snapshot whenever
    /// `exercise` is live and its name has changed since (defensive; nothing
    /// mutates this row's `exercise` today, but keeps it correct if that ever
    /// changes without every writer remembering to re-stamp the snapshot).
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

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        estimated1RM: Double? = nil,
        totalVolume: Double = 0,
        bestSetWeight: Double? = nil,
        bestSetReps: Int? = nil,
        setsPerformed: Int? = nil,
        avgRPE: Double? = nil,
        worstFormRaw: String? = nil,
        feedbackSampleCount: Int = 0,
        gassedFraction: Double? = nil,
        workoutPlanID: UUID? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.estimated1RM = estimated1RM
        self.totalVolume = totalVolume
        self.bestSetWeight = bestSetWeight
        self.bestSetReps = bestSetReps
        self.setsPerformed = setsPerformed
        self.avgRPE = avgRPE
        self.worstFormRaw = worstFormRaw
        self.feedbackSampleCount = feedbackSampleCount
        self.gassedFraction = gassedFraction
        self.workoutPlanID = workoutPlanID
        self.exercise = exercise
        exerciseNameSnapshot = exercise?.name
    }
}

// MARK: - DTO

extension ExerciseHistory {
    struct DTO: Codable {
        let id: UUID
        let date: Date
        let exercise_id: UUID?
        let estimated_1rm: Double?
        let total_volume: Double
        let best_set_weight: Double?
        let best_set_reps: Int?
        let sets_performed: Int?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            exercise_id: exercise?.id,
            estimated_1rm: estimated1RM,
            total_volume: totalVolume,
            best_set_weight: bestSetWeight,
            best_set_reps: bestSetReps,
            sets_performed: setsPerformed
        )
    }
}
