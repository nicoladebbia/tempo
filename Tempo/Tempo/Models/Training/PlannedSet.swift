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

    /// §11.12 — effort target: reps left in the tank when the set ends.
    /// Set by the e1RM-anchored prescription path; nil on warmups, legacy
    /// rows, and fallback prescriptions (optional → lightweight migration).
    var targetRIR: Int?

    // MARK: - Actuals

    var actualReps: Int?

    var actualWeight: Double?

    var rpe: Int?

    var completed: Bool

    var restSeconds: Int?

    var completedAt: Date?

    var isWarmup: Bool

    /// §5 (trainer-program effort prescriptions) — true for the FIRST working
    /// set of an exercise whose trainer-written % has no reliable e1RM to read
    /// it against (or is an isolation/machine lift, where % never means
    /// e1RM × %). No `targetWeight` is pre-filled: the athlete picks a weight
    /// live, and logging it derives an e1RM that sets every remaining set's
    /// target (see `TrainingViewModel.logSet` / `propagateCalibration`).
    /// Defaulted → SwiftData auto-migrates.
    var isCalibration: Bool = false

    /// Signed external load (kg) for bodyweight-loaded lifts (pull-ups, dips):
    /// positive = added weight (belt/vest), negative = assistance (band/machine
    /// help). nil for non-bodyweight lifts and legacy rows. `actualWeight` /
    /// `targetWeight` hold the EFFECTIVE load (bodyweight ± this), so
    /// e1RM/volume/progression need no special-casing; this field only records
    /// the signed input so history can show "BW + 10" / "BW − 20 (assisted)".
    /// Optional → lightweight SwiftData migration (nil on existing rows).
    var addedLoadKg: Double?

    /// §6.4/§7.7 — 1-based position of this row within a DROP SET sequence:
    /// the reduced-weight, no-rest continuation logged immediately after the
    /// set before it. nil = a normal set (working, warmup, or the initiating
    /// top set of a sequence — only the STEPS chained after it carry this).
    /// Drop steps are excluded from PR/e1RM detection (a reduced-weight
    /// backoff set is never a max-effort signal) but DO count toward volume
    /// and set-count, since the work was still performed.
    /// Optional → lightweight SwiftData migration (nil on existing rows).
    var dropStepIndex: Int?

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
        // A drop step is a reduced-weight backoff, never a max-effort signal —
        // excluded from e1RM/PR the same way warmup ramps are.
        guard completed, dropStepIndex == nil, let w = actualWeight, let r = actualReps, r > 0 else {
            return nil
        }
        if r == 1 {
            return w
        }
        return w * (1 + Double(r) / 30.0)
    }

    /// Whether this row is a reduced-weight drop step chained onto the set
    /// before it (§6.4). Read-only convenience over `dropStepIndex`.
    @Transient
    var isDropStep: Bool {
        dropStepIndex != nil
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
        targetRIR: Int? = nil,
        actualReps: Int? = nil,
        actualWeight: Double? = nil,
        rpe: Int? = nil,
        completed: Bool = false,
        restSeconds: Int? = nil,
        isWarmup: Bool = false,
        isCalibration: Bool = false,
        addedLoadKg: Double? = nil,
        dropStepIndex: Int? = nil,
        plannedExercise: PlannedExercise? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetRIR = targetRIR
        self.actualReps = actualReps
        self.actualWeight = actualWeight
        self.rpe = rpe
        self.completed = completed
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
        self.isCalibration = isCalibration
        self.addedLoadKg = addedLoadKg
        self.dropStepIndex = dropStepIndex
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
        let added_load_kg: Double?
        let drop_step_index: Int?
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
            is_warmup: isWarmup,
            added_load_kg: addedLoadKg,
            drop_step_index: dropStepIndex
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
