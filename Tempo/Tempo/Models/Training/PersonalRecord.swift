import Foundation
import SwiftData

@Model
final class PersonalRecord {

    @Attribute(.unique)
    var id: UUID

    var typeRaw: String

    var value: Double

    var date: Date

    var workoutPlanID: UUID?

    var context: String?

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    // MARK: - Computed

    @Transient
    var type: PRType {
        get { PRType(rawValue: typeRaw) ?? .oneRepMax }
        set { typeRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        type: PRType,
        value: Double,
        date: Date,
        workoutPlanID: UUID? = nil,
        context: String? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.value = value
        self.date = date
        self.workoutPlanID = workoutPlanID
        self.context = context
        self.exercise = exercise
    }
}

// MARK: - DTO

extension PersonalRecord {

    struct DTO: Codable, Sendable {
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
