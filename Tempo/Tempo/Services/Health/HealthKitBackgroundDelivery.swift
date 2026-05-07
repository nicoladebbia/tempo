//
// HealthKitBackgroundDelivery.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import HealthKit
import os

// MARK: - HealthKit Background Delivery

// Per INTEGRATION_SPECS.md Section 2.4 — Background delivery for steps, workouts, sleep.
// Per TECHNICAL_FEASIBILITY_AUDIT.md Section 1.2:
//   - .immediate may take 5-30 minutes (not real-time)
//   - Background delivery stops when app is force-quit
//   - CRITICAL: completionHandler MUST always be called

extension HealthKitService {
    // MARK: - Enable Background Delivery

    // Per INTEGRATION_SPECS.md Section 2.4 — must be called once during app initialization.

    func enableBackgroundDelivery() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            return
        }

        let typesAndFrequencies: [(HKObjectType, HKUpdateFrequency)] = [
            (HKQuantityType(.stepCount), .hourly),
            (HKQuantityType(.activeEnergyBurned), .hourly),
            (HKWorkoutType.workoutType(), .immediate),
            (HKCategoryType(.sleepAnalysis), .immediate),
        ]

        for (type, frequency) in typesAndFrequencies {
            do {
                try await healthStore.enableBackgroundDelivery(for: type, frequency: frequency)
                Logger.healthkit.info("Background delivery enabled for \(type.identifier)")
            } catch {
                Logger.healthkit.error("Failed to enable background delivery for \(type.identifier): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Setup Observer Queries

    // Per INTEGRATION_SPECS.md Section 2.4 — observer queries that fire on data changes.
    // CRITICAL: Every completionHandler MUST be called, even on error.
    // Failure to call completionHandler stops all future background deliveries.

    func setupObserverQueries() {
        // Steps observer
        let stepsQuery = HKObserverQuery(
            sampleType: HKQuantityType(.stepCount),
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            defer { completionHandler() }
            guard error == nil else {
                Logger.healthkit.debug("Steps observer error: \(error!.localizedDescription)")
                return
            }

            Task { [weak self] in
                guard let self else {
                    return
                }
                if let steps = try? await fetchSteps(for: Date()) {
                    Logger.healthkit.debug("Background step update: \(steps)")
                }
            }
        }
        healthStore.execute(stepsQuery)

        let workoutQuery = HKObserverQuery(
            sampleType: HKWorkoutType.workoutType(),
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            defer { completionHandler() }
            guard error == nil else {
                Logger.healthkit.debug("Workout observer error: \(error!.localizedDescription)")
                return
            }

            Task { [weak self] in
                guard let self else {
                    return
                }
                if let workouts = try? await fetchWorkouts(for: Date()) {
                    Logger.healthkit.debug("Background workout update: \(workouts.count) workouts")
                }
            }
        }
        healthStore.execute(workoutQuery)

        let sleepQuery = HKObserverQuery(
            sampleType: HKCategoryType(.sleepAnalysis),
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            defer { completionHandler() }
            guard error == nil else {
                Logger.healthkit.debug("Sleep observer error: \(error!.localizedDescription)")
                return
            }

            Task { [weak self] in
                guard let self else {
                    return
                }
                if let sleep = try? await fetchSleepAnalysis(for: Date()) {
                    Logger.healthkit.debug("Background sleep update: \(String(format: "%.1f", sleep.totalHours))h")
                }
            }
        }
        healthStore.execute(sleepQuery)

        Logger.healthkit.debug("Observer queries set up for steps, workouts, sleep")
    }
}
