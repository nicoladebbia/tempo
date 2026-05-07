//
// PlannedSet.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - PlannedSet

@Model
final class PlannedSet {
    @Attribute(.unique)
    var id: UUID

    var setNumber: Int

    // MARK: - Targets

    var targetReps: Int

    var targetWeight: Double?

    // MARK: - Actuals

    var actualReps: Int?

    var actualWeight: Double?

    var rpe: Int?

    var completed: Bool

    var restSeconds: Int?

    var completedAt: Date?

    var isWarmup: Bool

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var plannedExercise: PlannedExercise?

    // MARK: - Computed

    @Transient
    var volume: Double? {
        guard completed, let w = actualWeight, let r = actualReps else {
            return nil
        }
        return w * Double(r)
    }

    @Transient
    var estimated1RM: Double? {
        guard completed, let w = actualWeight, let r = actualReps, r > 0 else {
            return nil
        }
        if r == 1 {
            return w
        }
        return w * (1 + Double(r) / 30.0)
    }

    @Transient
    var metTarget: Bool {
        guard completed, let ar = actualReps else {
            return false
        }
        let weightMet = targetWeight == nil || (actualWeight ?? 0) >= (targetWeight ?? 0)
        return ar >= targetReps && weightMet
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        setNumber: Int,
        targetReps: Int,
        targetWeight: Double? = nil,
        actualReps: Int? = nil,
        actualWeight: Double? = nil,
        rpe: Int? = nil,
        completed: Bool = false,
        restSeconds: Int? = nil,
        isWarmup: Bool = false,
        plannedExercise: PlannedExercise? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.actualReps = actualReps
        self.actualWeight = actualWeight
        self.rpe = rpe
        self.completed = completed
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
        self.plannedExercise = plannedExercise
    }
}

// MARK: - DTO

extension PlannedSet {
    struct DTO: Codable {
        let id: UUID
        let set_number: Int
        let target_reps: Int
        let target_weight: Double?
        let actual_reps: Int?
        let actual_weight: Double?
        let rpe: Int?
        let completed: Bool
        let rest_seconds: Int?
        let completed_at: Date?
        let is_warmup: Bool
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            set_number: setNumber,
            target_reps: targetReps,
            target_weight: targetWeight,
            actual_reps: actualReps,
            actual_weight: actualWeight,
            rpe: rpe,
            completed: completed,
            rest_seconds: restSeconds,
            completed_at: completedAt,
            is_warmup: isWarmup
        )
    }
}

// MARK: - Validation

extension PlannedSet {
    enum ValidationError: LocalizedError {
        case invalidReps
        case invalidWeight
        case invalidRPE
        case invalidRestSeconds

        var errorDescription: String? {
            switch self {
            case .invalidReps: "Reps must be between 1 and 100."
            case .invalidWeight: "Weight must be between 0 and 500 kg."
            case .invalidRPE: "RPE must be between 1 and 10."
            case .invalidRestSeconds: "Rest must be between 0 and 600 seconds."
            }
        }
    }

    func validate() throws {
        guard (1 ... 100).contains(targetReps) else {
            throw ValidationError.invalidReps
        }
        if let w = targetWeight {
            guard (0 ... 500).contains(w) else {
                throw ValidationError.invalidWeight
            }
        }
        if let ar = actualReps {
            guard (1 ... 100).contains(ar) else {
                throw ValidationError.invalidReps
            }
        }
        if let aw = actualWeight {
            guard (0 ... 500).contains(aw) else {
                throw ValidationError.invalidWeight
            }
        }
        if let r = rpe {
            guard (1 ... 10).contains(r) else {
                throw ValidationError.invalidRPE
            }
        }
        if let rest = restSeconds {
            guard (0 ... 600).contains(rest) else {
                throw ValidationError.invalidRestSeconds
            }
        }
    }
}
