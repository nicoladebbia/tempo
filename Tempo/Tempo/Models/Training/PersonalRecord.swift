//
// PersonalRecord.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - PersonalRecord

@Model
final class PersonalRecord {
    @Attribute(.unique)
    var id: UUID

    var typeRaw: String

    var value: Double

    var date: Date

    var workoutPlanID: UUID?

    /// Legacy free-text context, e.g. "100 x 5 reps". Written unit-neutral
    /// (never bakes in "kg") — `value`/`contextWeightKg` are always kg
    /// internally; a reader that needs the user's unit should convert
    /// `contextWeightKg`/`contextReps` itself rather than display this raw.
    var context: String?

    /// The weight (kg) that produced this PR — same currency as `value`.
    /// Lets a reader format "100 kg x 5" / "220 lb x 5" in the user's own
    /// unit instead of trusting the unit-neutral `context` string.
    var contextWeightKg: Double?

    /// The rep count that produced this PR.
    var contextReps: Int?

    /// Exercise name captured at write time. `Exercise.personalRecords` is
    /// `.nullify` (§10.6) — deleting a custom exercise detaches `exercise`
    /// here rather than deleting the row, so this permanent record needs its
    /// own name to keep showing once that happens. nil while `exercise` is
    /// still set (read `exercise.name` — see `displayName`) or on legacy rows.
    var exerciseNameSnapshot: String?

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    // MARK: - Computed

    @Transient
    var type: PRType {
        get { PRType(rawValue: typeRaw) ?? .oneRepMax }
        set { typeRaw = newValue.rawValue }
    }

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
        type: PRType,
        value: Double,
        date: Date,
        workoutPlanID: UUID? = nil,
        context: String? = nil,
        contextWeightKg: Double? = nil,
        contextReps: Int? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        typeRaw = type.rawValue
        self.value = value
        self.date = date
        self.workoutPlanID = workoutPlanID
        self.context = context
        self.contextWeightKg = contextWeightKg
        self.contextReps = contextReps
        self.exercise = exercise
        exerciseNameSnapshot = exercise?.name
    }
}

// MARK: - DTO

extension PersonalRecord {
    struct DTO: Codable {
        let id: UUID
        let exercise_id: UUID?
        let type: String
        let value: Double
        let date: Date
        let workout_plan_id: UUID?
        let context: String?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            exercise_id: exercise?.id,
            type: typeRaw,
            value: value,
            date: date,
            workout_plan_id: workoutPlanID,
            context: context
        )
    }
}
