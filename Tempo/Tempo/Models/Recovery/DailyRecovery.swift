//
// DailyRecovery.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - DailyRecovery

@Model
final class DailyRecovery {
    @Attribute(.unique)
    var id: UUID

    @Attribute(.unique)
    var date: Date

    // MARK: - Recovery

    var recoveryScore: Double

    var recoveryZoneRaw: String

    // MARK: - HRV & Heart Rate

    var hrvRmssd: Double?

    var restingHR: Double?

    var spo2: Double?

    var skinTemp: Double?

    // MARK: - Sleep

    var sleepHours: Double?

    var sleepScore: Double?

    var sleepEfficiency: Double?

    var sleepConsistency: Double?

    var deepSleepMin: Int?

    var remSleepMin: Int?

    var lightSleepMin: Int?

    var awakeMin: Int?

    var sleepNeededBaseline: Double?

    var sleepDebt: Double?

    // MARK: - Respiratory

    var respiratoryRate: Double?

    // MARK: - Strain & Activity

    var strain: Double?

    var avgHR: Double?

    var maxHR: Double?

    var caloriesBurned: Double?

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \DailyPrescription.dailyRecovery)
    var prescription: DailyPrescription?

    // MARK: - Computed

    @Transient
    var recoveryZone: RecoveryZone {
        get { RecoveryZone(rawValue: recoveryZoneRaw) ?? RecoveryZone(score: recoveryScore) }
        set { recoveryZoneRaw = newValue.rawValue }
    }

    @Transient
    var totalSleepStageMinutes: Int {
        (deepSleepMin ?? 0) + (remSleepMin ?? 0) + (lightSleepMin ?? 0)
    }

    @Transient
    var deepSleepPercentage: Double? {
        guard let deep = deepSleepMin, totalSleepStageMinutes > 0 else {
            return nil
        }
        return Double(deep) / Double(totalSleepStageMinutes) * 100
    }

    @Transient
    var remSleepPercentage: Double? {
        guard let rem = remSleepMin, totalSleepStageMinutes > 0 else {
            return nil
        }
        return Double(rem) / Double(totalSleepStageMinutes) * 100
    }

    @Transient
    var isSleepDebtCritical: Bool {
        (sleepDebt ?? 0) >= 4.0
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        recoveryScore: Double,
        hrvRmssd: Double? = nil,
        restingHR: Double? = nil,
        spo2: Double? = nil,
        skinTemp: Double? = nil,
        sleepHours: Double? = nil,
        sleepScore: Double? = nil,
        sleepEfficiency: Double? = nil,
        sleepConsistency: Double? = nil,
        deepSleepMin: Int? = nil,
        remSleepMin: Int? = nil,
        lightSleepMin: Int? = nil,
        awakeMin: Int? = nil,
        sleepNeededBaseline: Double? = nil,
        sleepDebt: Double? = nil,
        respiratoryRate: Double? = nil,
        strain: Double? = nil,
        avgHR: Double? = nil,
        maxHR: Double? = nil,
        caloriesBurned: Double? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.recoveryScore = recoveryScore
        recoveryZoneRaw = RecoveryZone(score: recoveryScore).rawValue
        self.hrvRmssd = hrvRmssd
        self.restingHR = restingHR
        self.spo2 = spo2
        self.skinTemp = skinTemp
        self.sleepHours = sleepHours
        self.sleepScore = sleepScore
        self.sleepEfficiency = sleepEfficiency
        self.sleepConsistency = sleepConsistency
        self.deepSleepMin = deepSleepMin
        self.remSleepMin = remSleepMin
        self.lightSleepMin = lightSleepMin
        self.awakeMin = awakeMin
        self.sleepNeededBaseline = sleepNeededBaseline
        self.sleepDebt = sleepDebt
        self.respiratoryRate = respiratoryRate
        self.strain = strain
        self.avgHR = avgHR
        self.maxHR = maxHR
        self.caloriesBurned = caloriesBurned
    }
}

// MARK: - DTO

extension DailyRecovery {
    struct DTO: Codable {
        let id: UUID
        let date: Date
        let recovery_score: Double
        let recovery_zone: String
        let hrv_rmssd: Double?
        let resting_hr: Double?
        let spo2: Double?
        let skin_temp: Double?
        let sleep_hours: Double?
        let sleep_score: Double?
        let sleep_efficiency: Double?
        let sleep_consistency: Double?
        let deep_sleep_min: Int?
        let rem_sleep_min: Int?
        let light_sleep_min: Int?
        let awake_min: Int?
        let sleep_needed_baseline: Double?
        let sleep_debt: Double?
        let respiratory_rate: Double?
        let strain: Double?
        let avg_hr: Double?
        let max_hr: Double?
        let calories_burned: Double?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            recovery_score: recoveryScore,
            recovery_zone: recoveryZoneRaw,
            hrv_rmssd: hrvRmssd,
            resting_hr: restingHR,
            spo2: spo2,
            skin_temp: skinTemp,
            sleep_hours: sleepHours,
            sleep_score: sleepScore,
            sleep_efficiency: sleepEfficiency,
            sleep_consistency: sleepConsistency,
            deep_sleep_min: deepSleepMin,
            rem_sleep_min: remSleepMin,
            light_sleep_min: lightSleepMin,
            awake_min: awakeMin,
            sleep_needed_baseline: sleepNeededBaseline,
            sleep_debt: sleepDebt,
            respiratory_rate: respiratoryRate,
            strain: strain,
            avg_hr: avgHR,
            max_hr: maxHR,
            calories_burned: caloriesBurned
        )
    }
}
