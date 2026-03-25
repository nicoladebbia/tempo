import Foundation
import SwiftData

@Model
final class PlannedExercise {

    @Attribute(.unique)
    var id: UUID

    var order: Int

    var supersetGroup: Int?

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var workoutPlan: WorkoutPlan?

    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \PlannedSet.plannedExercise)
    var sets: [PlannedSet]?

    // MARK: - Computed

    @Transient
    var orderedSets: [PlannedSet] {
        (sets ?? []).sorted { $0.setNumber < $1.setNumber }
    }

    @Transient
    var isComplete: Bool {
        guard let sets, !sets.isEmpty else { return false }
        return sets.allSatisfy(\.completed)
    }

    @Transient
    var bestSet: PlannedSet? {
        (sets ?? [])
            .filter { $0.completed && $0.actualWeight != nil }
            .max { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) }
    }

    @Transient
    var totalVolume: Double {
        (sets ?? []).reduce(0) { total, set in
            guard set.completed,
                  let w = set.actualWeight,
                  let r = set.actualReps else { return total }
            return total + (w * Double(r))
        }
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
    }
}

// MARK: - DTO

extension PlannedExercise {

    struct DTO: Codable, Sendable {
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
