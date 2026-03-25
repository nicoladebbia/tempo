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
        guard HKHealthStore.isHealthDataAvailable() else { return }

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
                Logger.healthkit.error("Steps observer error: \(error!.localizedDescription)")
                return
            }

            Task { [weak self] in
                guard let self else { return }
                do {
                    let steps = try await self.fetchSteps(for: Date())
                    Logger.healthkit.debug("Background step update: \(steps)")
                } catch {
                    Logger.healthkit.error("Background step fetch failed: \(error.localizedDescription)")
                }
            }
        }
        healthStore.execute(stepsQuery)

        // Workout observer (immediate delivery)
        let workoutQuery = HKObserverQuery(
            sampleType: HKWorkoutType.workoutType(),
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            defer { completionHandler() }
            guard error == nil else {
                Logger.healthkit.error("Workout observer error: \(error!.localizedDescription)")
                return
            }

            Task { [weak self] in
                guard let self else { return }
                do {
                    let workouts = try await self.fetchWorkouts(for: Date())
                    Logger.healthkit.debug("Background workout update: \(workouts.count) workouts")
                } catch {
                    Logger.healthkit.error("Background workout fetch failed: \(error.localizedDescription)")
                }
            }
        }
        healthStore.execute(workoutQuery)

        // Sleep observer (immediate delivery)
        let sleepQuery = HKObserverQuery(
            sampleType: HKCategoryType(.sleepAnalysis),
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            defer { completionHandler() }
            guard error == nil else {
                Logger.healthkit.error("Sleep observer error: \(error!.localizedDescription)")
                return
            }

            Task { [weak self] in
                guard let self else { return }
                do {
                    let sleep = try await self.fetchSleepAnalysis(for: Date())
                    Logger.healthkit.debug("Background sleep update: \(String(format: "%.1f", sleep.totalHours))h")
                } catch {
                    Logger.healthkit.error("Background sleep fetch failed: \(error.localizedDescription)")
                }
            }
        }
        healthStore.execute(sleepQuery)

        Logger.healthkit.info("Observer queries set up for steps, workouts, sleep")
    }
}
