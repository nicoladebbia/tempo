//
// Exercise.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - Exercise

@Model
final class Exercise {
    @Attribute(.unique)
    var id: UUID

    var name: String

    var muscleGroupRaw: String

    var secondaryMusclesJSON: Data?

    var equipmentRaw: String

    var movementPatternRaw: String

    var isCompound: Bool

    var isCustom: Bool

    var demoAsset: String?

    var instructions: String?

    var cuesJSON: Data?

    var preferredRestSeconds: Int?

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.exercise)
    var plannedExercises: [PlannedExercise]?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseHistory.exercise)
    var history: [ExerciseHistory]?

    @Relationship(deleteRule: .cascade, inverse: \PersonalRecord.exercise)
    var personalRecords: [PersonalRecord]?

    // MARK: - Computed

    @Transient
    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .chest }
        set { muscleGroupRaw = newValue.rawValue }
    }

    @Transient
    var secondaryMuscles: [MuscleGroup] {
        get {
            guard let data = secondaryMusclesJSON,
                  let raw = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            return raw.compactMap { MuscleGroup(rawValue: $0) }
        }
        set {
            secondaryMusclesJSON = try? JSONEncoder().encode(newValue.map(\.rawValue))
        }
    }

    @Transient
    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .barbell }
        set { equipmentRaw = newValue.rawValue }
    }

    @Transient
    var movementPattern: MovementPattern {
        get { MovementPattern(rawValue: movementPatternRaw) ?? .horizontalPush }
        set { movementPatternRaw = newValue.rawValue }
    }

    @Transient
    var cues: [String] {
        get {
            guard let data = cuesJSON,
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            return decoded
        }
        set {
            cuesJSON = try? JSONEncoder().encode(newValue)
        }
    }

    /// Filename-safe slug for the pre-rendered exercise-name audio clip
    /// (cue_ex_<slug>). Mirrors WarmupMove.slug and the generator's slug() so
    /// runtime lookup and the bundled clips agree. Built-in library names have
    /// clips; custom exercises won't, and fall back to the Apple voice.
    var audioSlug: String {
        let lowered = name.lowercased()
        let mapped = lowered.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : "_"
        }
        var s = String(mapped)
        while s.contains("__") {
            s = s.replacingOccurrences(of: "__", with: "_")
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    @Transient
    var currentEstimated1RM: Double? {
        history?
            .sorted { $0.date > $1.date }
            .first?
            .estimated1RM
    }

    @Transient
    var allTimePR: Double? {
        personalRecords?
            .filter { $0.typeRaw == PRType.oneRepMax.rawValue }
            .max(by: { $0.value < $1.value })?
            .value
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: MuscleGroup,
        secondaryMuscles: [MuscleGroup] = [],
        equipment: Equipment,
        movementPattern: MovementPattern,
        isCompound: Bool,
        isCustom: Bool = false,
        demoAsset: String? = nil,
        instructions: String? = nil,
        cues: [String] = []
    ) {
        self.id = id
        self.name = name
        muscleGroupRaw = muscleGroup.rawValue
        secondaryMusclesJSON = try? JSONEncoder().encode(secondaryMuscles.map(\.rawValue))
        equipmentRaw = equipment.rawValue
        movementPatternRaw = movementPattern.rawValue
        self.isCompound = isCompound
        self.isCustom = isCustom
        self.demoAsset = demoAsset
        self.instructions = instructions
        cuesJSON = try? JSONEncoder().encode(cues)
    }
}

// MARK: - DTO

extension Exercise {
    struct DTO: Codable {
        let id: UUID
        let name: String
        let muscle_group: String
        let secondary_muscles: [String]
        let equipment: String
        let movement_pattern: String
        let is_compound: Bool
        let is_custom: Bool
        let demo_asset: String?
        let instructions: String?
        let cues: [String]
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            name: name,
            muscle_group: muscleGroupRaw,
            secondary_muscles: secondaryMuscles.map(\.rawValue),
            equipment: equipmentRaw,
            movement_pattern: movementPatternRaw,
            is_compound: isCompound,
            is_custom: isCustom,
            demo_asset: demoAsset,
            instructions: instructions,
            cues: cues
        )
    }
}
