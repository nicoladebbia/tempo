import Foundation
import SwiftData

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
                  let raw = try? JSONDecoder().decode([String].self, from: data) else {
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
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            cuesJSON = try? JSONEncoder().encode(newValue)
        }
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
        self.muscleGroupRaw = muscleGroup.rawValue
        self.secondaryMusclesJSON = try? JSONEncoder().encode(secondaryMuscles.map(\.rawValue))
        self.equipmentRaw = equipment.rawValue
        self.movementPatternRaw = movementPattern.rawValue
        self.isCompound = isCompound
        self.isCustom = isCustom
        self.demoAsset = demoAsset
        self.instructions = instructions
        self.cuesJSON = try? JSONEncoder().encode(cues)
    }
}

// MARK: - DTO

extension Exercise {

    struct DTO: Codable, Sendable {
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
