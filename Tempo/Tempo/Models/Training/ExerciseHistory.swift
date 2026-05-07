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

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        estimated1RM: Double? = nil,
        totalVolume: Double = 0,
        bestSetWeight: Double? = nil,
        bestSetReps: Int? = nil,
        setsPerformed: Int? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.estimated1RM = estimated1RM
        self.totalVolume = totalVolume
        self.bestSetWeight = bestSetWeight
        self.bestSetReps = bestSetReps
        self.setsPerformed = setsPerformed
        self.exercise = exercise
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
