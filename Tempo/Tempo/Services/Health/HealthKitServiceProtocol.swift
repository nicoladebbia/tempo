//
// HealthKitServiceProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - HealthKitServiceProtocol

protocol HealthKitServiceProtocol: Sendable {
    func requestAuthorization() async throws
    func fetchSteps(for date: Date) async throws -> Int
    func fetchActiveEnergy(for date: Date) async throws -> Double
    func fetchHeartRate(for date: Date) async throws -> [HeartRateSample]
    func fetchHRV(for date: Date) async throws -> Double?
    func fetchRestingHeartRate(for date: Date) async throws -> Double?
    func fetchSleepAnalysis(for date: Date) async throws -> SleepData
    func fetchWorkouts(for date: Date) async throws -> [WorkoutSample]
    func fetchBodyComposition() async throws -> BodyCompositionData
    /// Live biometrics for TDEE / meal-plan generation. Pulls weight, height,
    /// body fat from quantity samples and age, biological sex from
    /// `HKCharacteristicType`. Any missing piece comes back nil so the caller
    /// can decide what to do (block, fall back, prompt the user).
    func fetchBiometricsSnapshot() async throws -> BiometricsSnapshot
    func writeWorkout(_ workout: WorkoutSample) async throws
    func writeNutrition(_ nutrition: NutritionSample) async throws
    func enableBackgroundDelivery() async throws
}

// MARK: - HeartRateSample

struct HeartRateSample {
    let timestamp: Date
    let bpm: Double
}

// MARK: - SleepData

struct SleepData {
    let totalHours: Double
    let deepSleepMinutes: Int
    let remSleepMinutes: Int
    let lightSleepMinutes: Int
    let awakeMinutes: Int
    let sleepEfficiency: Double
    let bedtime: Date?
    let wakeTime: Date?

    var sleepScore: Int {
        // Simplified scoring: efficiency * weight + duration * weight
        let efficiencyScore = min(sleepEfficiency / 100.0, 1.0) * 50
        let durationScore = min(totalHours / 8.0, 1.0) * 30
        let deepScore = min(Double(deepSleepMinutes) / 90.0, 1.0) * 20
        return Int(efficiencyScore + durationScore + deepScore)
    }
}

// MARK: - WorkoutSample

struct WorkoutSample {
    let startDate: Date
    let endDate: Date
    let workoutType: String
    let durationMinutes: Double
    let activeCalories: Double
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let distanceMeters: Double?
}

// MARK: - BodyCompositionData

struct BodyCompositionData {
    let weightKg: Double?
    let bodyFatPercent: Double?
    let leanMassKg: Double?
    let heightCm: Double?
    let measurementDate: Date?

    /// Computed muscle mass estimate (lean mass minus ~15% bone/organ mass)
    var estimatedMuscleMassKg: Double? {
        guard let lean = leanMassKg else {
            return nil
        }
        return lean * 0.85
    }

    var fatMassKg: Double? {
        guard let w = weightKg, let bf = bodyFatPercent else {
            return nil
        }
        return w * (bf / 100.0)
    }
}

// MARK: - BiometricsSnapshot

/// Live biometrics pulled from HealthKit on demand. Distinct from
/// `BodyCompositionData` because it carries the two `HKCharacteristicType`
/// values (age, sex) that `BodyCompositionData` does not, plus it's the
/// authoritative source for TDEE / meal-plan generation. The caller treats
/// this as the **only** source of truth — `DietaryProfile` is just a cache.
///
/// Fields are optional so the caller (BiometricsSyncService) can detect a
/// missing value and surface "open the Health app" rather than silently
/// substituting a default.
struct BiometricsSnapshot: Sendable, Equatable {
    let weightKg: Double?
    let heightCm: Double?
    let age: Int?
    let biologicalSex: BiologicalSex?
    let bodyFatPercent: Double?
    let measurementDate: Date?

    /// True when every field required for TDEE (Mifflin-St Jeor) is present.
    /// Body fat is optional (Katch-McArdle blend only kicks in when known).
    var isCompleteForTDEE: Bool {
        weightKg != nil && heightCm != nil && age != nil && biologicalSex != nil
    }
}

// MARK: - NutritionSample

struct NutritionSample {
    let date: Date
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
}
