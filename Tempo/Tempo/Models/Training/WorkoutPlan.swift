//
// WorkoutPlan.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - WorkoutPlan

@Model
final class WorkoutPlan {
    @Attribute(.unique)
    var id: UUID

    var date: Date

    var typeRaw: String

    var recoveryAdjustment: Double

    var statusRaw: String

    var durationMinutes: Int?

    var notes: String?

    var startedAt: Date?

    var finishedAt: Date?

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.workoutPlan)
    var exercises: [PlannedExercise]?

    // MARK: - Computed

    @Transient
    var type: WorkoutType {
        get { WorkoutType(rawValue: typeRaw) ?? .rest }
        set { typeRaw = newValue.rawValue }
    }

    @Transient
    var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    @Transient
    var orderedExercises: [PlannedExercise] {
        (exercises ?? []).sorted { $0.order < $1.order }
    }

    @Transient
    var totalSets: Int {
        (exercises ?? []).reduce(0) { $0 + ($1.sets?.count ?? 0) }
    }

    @Transient
    var completedSets: Int {
        (exercises ?? []).reduce(0) { total, ex in
            total + (ex.sets ?? []).filter(\.completed).count
        }
    }

    @Transient
    var completionPercentage: Double {
        guard totalSets > 0 else {
            return 0
        }
        return Double(completedSets) / Double(totalSets)
    }

    @Transient
    var totalVolume: Double {
        (exercises ?? []).reduce(0) { total, ex in
            total + (ex.sets ?? []).reduce(0) { setTotal, set in
                guard set.completed,
                      let weight = set.actualWeight,
                      let reps = set.actualReps
                else {
                    return setTotal
                }
                return setTotal + (weight * Double(reps))
            }
        }
    }

    @Transient
    var actualDurationMinutes: Int? {
        guard let start = startedAt, let end = finishedAt else {
            return nil
        }
        return Int(end.timeIntervalSince(start) / 60)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        type: WorkoutType,
        recoveryAdjustment: Double = 1.0,
        status: WorkoutStatus = .planned,
        durationMinutes: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        typeRaw = type.rawValue
        self.recoveryAdjustment = recoveryAdjustment
        statusRaw = status.rawValue
        self.durationMinutes = durationMinutes
        self.notes = notes
    }
}

// MARK: - DTO

extension WorkoutPlan {
    struct DTO: Codable {
        let id: UUID
        let date: Date
        let type: String
        let recovery_adjustment: Double
        let status: String
        let duration_minutes: Int?
        let notes: String?
        let started_at: Date?
        let finished_at: Date?
        let exercises: [PlannedExercise.DTO]?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            type: typeRaw,
            recovery_adjustment: recoveryAdjustment,
            status: statusRaw,
            duration_minutes: durationMinutes,
            notes: notes,
            started_at: startedAt,
            finished_at: finishedAt,
            exercises: orderedExercises.map { $0.toDTO() }
        )
    }
}
