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

    /// Whether the user completed (or worked through) the guided general
    /// warm-up + mobility block for this session. The block logs no sets — this
    /// flag is the only record that it happened, shown in the summary/history.
    /// Defaulted, so SwiftData migrates it automatically (no manual migration).
    var warmupCompleted: Bool = false

    var startedAt: Date?

    var finishedAt: Date?

    /// Why a `.skipped` day was skipped (INTELLIGENT_TRAINING_SYSTEM §8/§15.2).
    /// Distinguishes a FLOOR-FORCED skip ("body said recover" — must NOT count
    /// against adherence/streak) from a USER skip (counts). Adherence logic reads
    /// this, not just `status`. Defaulted nil → SwiftData auto-migrates.
    var skipReasonRaw: String?

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

    /// Why this day was skipped, when `status == .skipped` (§8/§15.2). nil = not
    /// skipped, or legacy skip with no reason recorded.
    @Transient
    var skipReason: SkipReason? {
        get { skipReasonRaw.flatMap(SkipReason.init(rawValue:)) }
        set { skipReasonRaw = newValue?.rawValue }
    }

    @Transient
    var orderedExercises: [PlannedExercise] {
        (exercises ?? []).sorted { $0.order < $1.order }
    }

    @Transient
    var totalSets: Int {
        // Working sets only — warmup ramp sets are not counted toward the
        // "X / Y sets" progress (exercise 0's warmups are skipped, never
        // logged, so counting them stranded the total at e.g. 19/21).
        (exercises ?? []).reduce(0) { $0 + ($1.sets ?? []).filter { !$0.isWarmup }.count }
    }

    @Transient
    var completedSets: Int {
        // Working sets only, to match totalSets.
        (exercises ?? []).reduce(0) { total, ex in
            total + (ex.sets ?? []).filter { !$0.isWarmup && $0.completed }.count
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
