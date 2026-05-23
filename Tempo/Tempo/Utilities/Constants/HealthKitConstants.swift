//
// HealthKitConstants.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import HealthKit

// MARK: - HealthKitConstants

// Per INTEGRATION_SPECS.md Section 2.1 — Exact HKObjectType sets.

enum HealthKitConstants {
    // MARK: - Read Types

    /// Types we READ from HealthKit.
    /// Per INTEGRATION_SPECS.md Section 2.1 — 16+ types across activity, heart, sleep, nutrition, body, workouts.
    static let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = [
            // Activity
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.appleExerciseTime),

            // Heart
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),

            // Sleep
            HKCategoryType(.sleepAnalysis),

            // Nutrition (to read what Whoop/other apps write)
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),

            // Body (Withings scale syncs weight, body fat, lean mass to HealthKit)
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.leanBodyMass),

            // Characteristics — date of birth + biological sex are the
            // single source of truth for age + sex used in TDEE / Mifflin-St
            // Jeor. Tempo will not store these directly; biometrics flow
            // HealthKit → DietaryProfile each sync, never the other way.
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),

            // Workouts
            HKWorkoutType.workoutType(),
        ]

        // iOS 17+: workout route for GPS data
        types.insert(HKSeriesType.workoutRoute())

        return types
    }()

    // MARK: - Write Types

    /// Types we WRITE to HealthKit.
    /// Per INTEGRATION_SPECS.md Section 2.1 — workouts from RepForge, nutrition from native logging.
    static let writeTypes: Set<HKSampleType> = [
        // Workouts logged in RepForge
        HKWorkoutType.workoutType(),

        // Nutrition from native meal logging
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryFiber),
        HKQuantityType(.dietarySugar),
        HKQuantityType(.dietarySodium),
    ]

    // MARK: - Background Task Identifiers

    /// BGTask identifier for HealthKit background refresh.
    static let backgroundRefreshTaskIdentifier = "com.tempo.healthkit.refresh"

    /// BGTask identifier for HealthKit background processing.
    static let backgroundProcessingTaskIdentifier = "com.tempo.healthkit.processing"
}

// MARK: - HealthKitAuthResult

// Per INTEGRATION_SPECS.md Section 2.1 — authorization result enum.

enum HealthKitAuthResult {
    /// All requested write types granted (read permissions are unknowable per Apple privacy design)
    case fullAccess
    /// Some write types denied
    case partialAccess(denied: [String])
    /// All write types denied
    case denied
    /// HealthKit not available on this device (iPad, iPod touch, etc.)
    case unavailable
    /// System error during authorization
    case error(Error)

    var isUsable: Bool {
        switch self {
        case .fullAccess,
             .partialAccess: true
        case .denied,
             .unavailable,
             .error: false
        }
    }
}
