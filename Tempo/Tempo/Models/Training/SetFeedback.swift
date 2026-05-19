//
// SetFeedback.swift
// Tempo
//
// Created by Tempo on 19/05/2026.
//

import Foundation
import SwiftData

// MARK: - BreathDifficulty

/// How hard the user was breathing right after a working set. Three rungs,
/// no more — this is a fast tap during rest, not a survey. Aggregated over
/// weeks the AI learns which loads push the user into `gassed` and biases
/// volume/rest prescription accordingly.
enum BreathDifficulty: String, Codable, CaseIterable, Sendable {
    case easy
    case moderate
    case gassed

    /// User-facing label. From UX_COPY_BIBLE `training.feedback.breath.*`.
    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .gassed: "Gassed"
        }
    }

    /// SF Symbol paired with the chip — icon scanning beats word scanning
    /// mid-workout.
    var symbolName: String {
        switch self {
        case .easy: "wind"
        case .moderate: "lungs.fill"
        case .gassed: "lungs"
        }
    }

    /// True when this signals the set taxed conditioning hard. Fed into
    /// future workout generation as a "back off" signal.
    var isNegativeSignal: Bool {
        self == .gassed
    }
}

// MARK: - FormQuality

/// Self-reported movement quality on the set. `failed` means the rep
/// pattern broke down (grinder / missed reps), distinct from a low RPE —
/// the AI treats `failed` as a hard regression signal even when the weight
/// was completed.
enum FormQuality: String, Codable, CaseIterable, Sendable {
    case clean
    case sloppy
    case failed

    /// User-facing label. From UX_COPY_BIBLE `training.feedback.form.*`.
    var displayName: String {
        switch self {
        case .clean: "Clean"
        case .sloppy: "Sloppy"
        case .failed: "Failed"
        }
    }

    var symbolName: String {
        switch self {
        case .clean: "checkmark.seal.fill"
        case .sloppy: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    /// True when the planner should bias away from this load next time.
    var isNegativeSignal: Bool {
        self == .sloppy || self == .failed
    }
}

// MARK: - SetFeedback

/// User feedback on a single completed `PlannedSet`, captured by
/// `SetFeedbackSheet` right after the set (on "Finish Set" or rest-timer
/// expiry). Read by `TrainingViewModel` so future workout generation can
/// incorporate historical difficulty signals.
///
/// Design notes:
/// - Linked to `PlannedSet` via a one-way `@Relationship(deleteRule:
///   .nullify)` — NOT a stored `PersistentIdentifier`. `PersistentIdentifier`
///   is not cleanly `#Predicate`-queryable and is not stable across stores.
///   This mirrors `MealFeedback.plannedMeal` exactly.
/// - `setID` is the denormalized stable `PlannedSet.id` (UUID) at capture
///   time. Survives the set being pruned and is what the sync DTO carries.
/// - Enums are stored as raw strings (SwiftData-native) with `@Transient`
///   typed accessors, per the project's model convention.
@Model
final class SetFeedback {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    var capturedAt: Date

    // MARK: - Scope

    /// The set this feedback is about. Nullified if the set is deleted;
    /// `setID` below survives for historical AI lookup.
    @Relationship(deleteRule: .nullify)
    var plannedSet: PlannedSet?

    /// Denormalized stable `PlannedSet.id` at capture time. Lets the
    /// training engine group feedback by set even after old workout rows
    /// are pruned, and is the identifier used by the sync DTO.
    var setID: UUID

    // MARK: - Content

    /// Rate of Perceived Exertion, 1–10. Clamped on init.
    var rpe: Int

    /// Breathing difficulty. Stored as `BreathDifficulty.rawValue`;
    /// `breathDifficulty` is the typed accessor.
    var breathDifficultyRaw: String

    /// Movement quality. Stored as `FormQuality.rawValue`; `formQuality`
    /// is the typed accessor.
    var formQualityRaw: String

    /// Optional free-text note ("left knee tweaked", "felt strong").
    var note: String?

    // MARK: - Typed Accessors

    @Transient
    var breathDifficulty: BreathDifficulty {
        get { BreathDifficulty(rawValue: breathDifficultyRaw) ?? .moderate }
        set { breathDifficultyRaw = newValue.rawValue }
    }

    @Transient
    var formQuality: FormQuality {
        get { FormQuality(rawValue: formQualityRaw) ?? .clean }
        set { formQualityRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        plannedSet: PlannedSet? = nil,
        setID: UUID? = nil,
        rpe: Int,
        breathDifficulty: BreathDifficulty = .moderate,
        formQuality: FormQuality = .clean,
        note: String? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.plannedSet = plannedSet
        self.setID = setID ?? plannedSet?.id ?? UUID()
        // RPE is 1–10 by UX contract; clamp defensively.
        self.rpe = max(1, min(10, rpe))
        self.breathDifficultyRaw = breathDifficulty.rawValue
        self.formQualityRaw = formQuality.rawValue
        self.note = note
    }
}

// MARK: - DTO

extension SetFeedback {
    struct DTO: Codable {
        let id: UUID
        let set_id: UUID
        let rpe: Int
        let breath_difficulty: String
        let form_quality: String
        let note: String?
        let captured_at: Date
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            set_id: setID,
            rpe: rpe,
            breath_difficulty: breathDifficultyRaw,
            form_quality: formQualityRaw,
            note: note,
            captured_at: capturedAt
        )
    }
}
