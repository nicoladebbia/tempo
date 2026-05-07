//
// DailySnapshot.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - DailySnapshot

/// PERFORMANCE NOTE: DailySnapshot has ~30 stored properties. This is at the upper limit
/// for SwiftData fetch performance. If fetch times degrade (>50ms for single-row lookup),
/// consider splitting into DailySnapshot (core fields: date, scores, compliance) and
/// DailySnapshotDetail (individual metrics). For now, 30 properties on a single-row-per-day
/// model is acceptable — the total row count stays low (~365/year).
@Model
final class DailySnapshot {
    @Attribute(.unique)
    var id: UUID

    /// Calendar date (normalized to midnight UTC). Unique constraint.
    @Attribute(.unique)
    var date: Date

    // MARK: - Body (Whoop + HealthKit)

    var recoveryScore: Double?

    var hrv: Double?

    var rhr: Double?

    var sleepHours: Double?

    var sleepScore: Double?

    var strain: Double?

    // MARK: - Fuel (NutriTrack)

    var caloriesConsumed: Int?

    var calorieTarget: Int?

    var proteinActual: Double?
    var carbsActual: Double?
    var fatActual: Double?

    var proteinTarget: Double?
    var carbsTarget: Double?
    var fatTarget: Double?

    var mealsLogged: Int

    var mealsPlanned: Int

    // MARK: - Mind (Local)

    var studyMinutes: Int

    var studyTarget: Int

    // MARK: - Move (HealthKit + Local)

    var steps: Int?

    var activeCalories: Double?

    var workoutCompleted: Bool

    var workoutTypeRaw: String?

    // MARK: - Body Extended (Whoop via DailyRecovery)

    var spo2: Double?

    var skinTemp: Double?

    // MARK: - Score

    var dailyScore: Int

    var nonNegotiablesCompleted: Int

    var nonNegotiablesTotal: Int

    // MARK: - Timestamps

    var updatedAt: Date

    // MARK: - Computed Properties

    @Transient
    var workoutType: WorkoutType? {
        get { workoutTypeRaw.flatMap { WorkoutType(rawValue: $0) } }
        set { workoutTypeRaw = newValue?.rawValue }
    }

    @Transient
    var calorieCompliance: Double? {
        guard let consumed = caloriesConsumed, let target = calorieTarget, target > 0 else {
            return nil
        }
        return Double(consumed) / Double(target)
    }

    @Transient
    var proteinCompliance: Double? {
        guard let actual = proteinActual, let target = proteinTarget, target > 0 else {
            return nil
        }
        return actual / target
    }

    @Transient
    var studyCompliance: Double {
        guard studyTarget > 0 else {
            return 1.0
        }
        return Double(studyMinutes) / Double(studyTarget)
    }

    @Transient
    var nonNegotiableCompliance: Double {
        guard nonNegotiablesTotal > 0 else {
            return 1.0
        }
        return Double(nonNegotiablesCompleted) / Double(nonNegotiablesTotal)
    }

    @Transient
    var recoveryZone: RecoveryZone? {
        recoveryScore.map { RecoveryZone(score: $0) }
    }

    @Transient
    var macrosOnTarget: Bool {
        guard let pA = proteinActual, let pT = proteinTarget, pT > 0,
              let cA = carbsActual, let cT = carbsTarget, cT > 0,
              let fA = fatActual, let fT = fatTarget, fT > 0
        else {
            return false
        }
        let tolerance = 0.10
        return abs(pA - pT) / pT <= tolerance &&
            abs(cA - cT) / cT <= tolerance &&
            abs(fA - fT) / fT <= tolerance
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        recoveryScore: Double? = nil,
        hrv: Double? = nil,
        rhr: Double? = nil,
        sleepHours: Double? = nil,
        sleepScore: Double? = nil,
        strain: Double? = nil,
        caloriesConsumed: Int? = nil,
        calorieTarget: Int? = nil,
        proteinActual: Double? = nil,
        carbsActual: Double? = nil,
        fatActual: Double? = nil,
        proteinTarget: Double? = nil,
        carbsTarget: Double? = nil,
        fatTarget: Double? = nil,
        mealsLogged: Int = 0,
        mealsPlanned: Int = 3,
        studyMinutes: Int = 0,
        studyTarget: Int = 120,
        steps: Int? = nil,
        activeCalories: Double? = nil,
        workoutCompleted: Bool = false,
        workoutType: WorkoutType? = nil,
        dailyScore: Int = 0,
        nonNegotiablesCompleted: Int = 0,
        nonNegotiablesTotal: Int = 0
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.recoveryScore = recoveryScore
        self.hrv = hrv
        self.rhr = rhr
        self.sleepHours = sleepHours
        self.sleepScore = sleepScore
        self.strain = strain
        self.caloriesConsumed = caloriesConsumed
        self.calorieTarget = calorieTarget
        self.proteinActual = proteinActual
        self.carbsActual = carbsActual
        self.fatActual = fatActual
        self.proteinTarget = proteinTarget
        self.carbsTarget = carbsTarget
        self.fatTarget = fatTarget
        self.mealsLogged = mealsLogged
        self.mealsPlanned = mealsPlanned
        self.studyMinutes = studyMinutes
        self.studyTarget = studyTarget
        self.steps = steps
        self.activeCalories = activeCalories
        self.workoutCompleted = workoutCompleted
        workoutTypeRaw = workoutType?.rawValue
        self.dailyScore = dailyScore
        self.nonNegotiablesCompleted = nonNegotiablesCompleted
        self.nonNegotiablesTotal = nonNegotiablesTotal
        updatedAt = Date()
    }
}

// MARK: - Codable DTO

extension DailySnapshot {
    struct DTO: Codable {
        let id: UUID
        let date: Date
        let recovery_score: Double?
        let hrv: Double?
        let rhr: Double?
        let sleep_hours: Double?
        let sleep_score: Double?
        let strain: Double?
        let calories_consumed: Int?
        let calorie_target: Int?
        let protein_actual: Double?
        let carbs_actual: Double?
        let fat_actual: Double?
        let protein_target: Double?
        let carbs_target: Double?
        let fat_target: Double?
        let meals_logged: Int
        let meals_planned: Int
        let study_minutes: Int
        let study_target: Int
        let steps: Int?
        let active_calories: Double?
        let workout_completed: Bool
        let workout_type: String?
        let daily_score: Int
        let non_negotiables_completed: Int
        let non_negotiables_total: Int
        let updated_at: Date
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            recovery_score: recoveryScore,
            hrv: hrv,
            rhr: rhr,
            sleep_hours: sleepHours,
            sleep_score: sleepScore,
            strain: strain,
            calories_consumed: caloriesConsumed,
            calorie_target: calorieTarget,
            protein_actual: proteinActual,
            carbs_actual: carbsActual,
            fat_actual: fatActual,
            protein_target: proteinTarget,
            carbs_target: carbsTarget,
            fat_target: fatTarget,
            meals_logged: mealsLogged,
            meals_planned: mealsPlanned,
            study_minutes: studyMinutes,
            study_target: studyTarget,
            steps: steps,
            active_calories: activeCalories,
            workout_completed: workoutCompleted,
            workout_type: workoutTypeRaw,
            daily_score: dailyScore,
            non_negotiables_completed: nonNegotiablesCompleted,
            non_negotiables_total: nonNegotiablesTotal,
            updated_at: updatedAt
        )
    }
}
