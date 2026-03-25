import Foundation
import HealthKit
import UIKit
import os

// MARK: - HealthKit Service (Real Implementation)
// Per INTEGRATION_SPECS.md Section 2.1 — Real HKHealthStore implementation.
// Per BUILD_PLAN.md Step 5.1 — Authorization flow, partial handling, logging.
// Fetch/write methods are stubs (implemented in steps 5.2-5.7).

final class HealthKitService: HealthKitServiceProtocol, @unchecked Sendable {

    // MARK: - Properties

    private let healthStore = HKHealthStore()

    /// Current authorization result. Updated on authorization and on every foreground check.
    private(set) var authResult: HealthKitAuthResult = .unavailable

    /// Tracks previous write status for revocation detection.
    /// Per INTEGRATION_SPECS.md Section 2.1 — detect permission revocation on app launch.
    private var previousWriteStatus: HKAuthorizationStatus = .notDetermined

    // MARK: - Authorization
    // Per INTEGRATION_SPECS.md Section 2.1 — requestAuthorization()

    func requestAuthorization() async throws {
        // Per INTEGRATION_SPECS.md: iPad, iPod touch — HealthKit unavailable.
        guard HKHealthStore.isHealthDataAvailable() else {
            authResult = .unavailable
            Logger.healthkit.warning("HealthKit not available on this device")
            return
        }

        do {
            try await healthStore.requestAuthorization(
                toShare: HealthKitConstants.writeTypes,
                read: HealthKitConstants.readTypes
            )

            // Check what was actually granted
            authResult = checkWriteAuthorizationStatus()
            Logger.healthkit.info("HealthKit authorization completed: \(String(describing: self.authResult))")
        } catch {
            authResult = .error(error)
            Logger.healthkit.error("HealthKit authorization failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Permission Verification
    // Per INTEGRATION_SPECS.md Section 2.1 — verifyPermissionsOnLaunch()
    // Must be called on every app launch and every return to foreground.

    func verifyPermissionsOnLaunch() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authResult = .unavailable
            return
        }

        // Check write permissions (these ARE queryable)
        let workoutStatus = healthStore.authorizationStatus(for: HKWorkoutType.workoutType())
        if workoutStatus == .sharingDenied && previousWriteStatus == .sharingAuthorized {
            Logger.healthkit.warning("HealthKit write permission revoked by user")
            authResult = .denied
        }
        previousWriteStatus = workoutStatus

        // Update full write status
        if case .denied = authResult {} else {
            authResult = checkWriteAuthorizationStatus()
        }

        // Attempt a lightweight read query to detect read permission revocation.
        // Per INTEGRATION_SPECS.md: read permission revocation is not directly queryable.
        do {
            let stepType = HKQuantityType(.stepCount)
            let predicate = HKQuery.predicateForSamples(
                withStart: Calendar.current.startOfDay(for: Date()),
                end: Date(),
                options: .strictStartDate
            )
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: stepType, predicate: predicate)],
                sortDescriptors: [],
                limit: 1
            )
            _ = try await descriptor.result(for: healthStore)
        } catch {
            Logger.healthkit.warning("HealthKit read query failed on launch: \(error.localizedDescription)")
        }
    }

    // MARK: - Check Authorization Status
    // Per INTEGRATION_SPECS.md Section 2.1 — checkAuthorizationStatus()
    // NOTE: Read permissions are unknowable per Apple privacy design.
    // We can only check write type authorization.

    private func checkWriteAuthorizationStatus() -> HealthKitAuthResult {
        var deniedTypes: [String] = []

        for type in HealthKitConstants.writeTypes {
            let status = healthStore.authorizationStatus(for: type)
            if status == .sharingDenied {
                deniedTypes.append(type.identifier)
            }
        }

        if deniedTypes.isEmpty {
            return .fullAccess
        } else if deniedTypes.count == HealthKitConstants.writeTypes.count {
            return .denied
        } else {
            return .partialAccess(denied: deniedTypes)
        }
    }

    // MARK: - Open Health Settings
    // Per INTEGRATION_SPECS.md Section 2.1 — guide user to Settings for re-enabling.

    @MainActor
    func openHealthSettings() {
        if let url = URL(string: "x-apple-health://") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Fetch Steps + Active Energy
    // Per INTEGRATION_SPECS.md Section 2.2.1 — HKStatisticsQuery with .cumulativeSum.
    // Automatically deduplicates across sources (iPhone + Apple Watch).

    func fetchSteps(for date: Date) async throws -> Int {
        let start = Date()
        let stepType = HKQuantityType(.stepCount)
        let (startOfDay, endOfDay) = dayBounds(for: date)
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        let statistics = try await fetchCumulativeStatistics(
            type: stepType,
            predicate: predicate
        )

        let steps = Int(statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
        let elapsed = Date().timeIntervalSince(start) * 1000
        Logger.healthkit.debug("fetchSteps: \(steps) steps in \(String(format: "%.0f", elapsed))ms")
        return steps
    }

    func fetchActiveEnergy(for date: Date) async throws -> Double {
        let start = Date()
        let energyType = HKQuantityType(.activeEnergyBurned)
        let (startOfDay, endOfDay) = dayBounds(for: date)
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        let statistics = try await fetchCumulativeStatistics(
            type: energyType,
            predicate: predicate
        )

        let calories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        let elapsed = Date().timeIntervalSince(start) * 1000
        Logger.healthkit.debug("fetchActiveEnergy: \(String(format: "%.0f", calories)) kcal in \(String(format: "%.0f", elapsed))ms")
        return calories
    }

    // MARK: - Statistics Query Helper

    private func fetchCumulativeStatistics(
        type: HKQuantityType,
        predicate: NSPredicate
    ) async throws -> HKStatistics? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: statistics)
                }
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Day Bounds Helper

    private func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return (startOfDay, endOfDay)
    }

    func fetchHeartRate(for date: Date) async throws -> [HeartRateSample] {
        // Step 5.3: Real implementation
        Logger.healthkit.debug("fetchHeartRate called — stub returning empty")
        return []
    }

    func fetchHRV(for date: Date) async throws -> Double? {
        // Step 5.3: Real implementation
        Logger.healthkit.debug("fetchHRV called — stub returning nil")
        return nil
    }

    func fetchRestingHeartRate(for date: Date) async throws -> Double? {
        // Step 5.3: Real implementation
        Logger.healthkit.debug("fetchRestingHeartRate called — stub returning nil")
        return nil
    }

    func fetchSleepAnalysis(for date: Date) async throws -> SleepData {
        // Step 5.4: Real implementation
        Logger.healthkit.debug("fetchSleepAnalysis called — stub returning empty")
        return SleepData(
            totalHours: 0,
            deepSleepMinutes: 0,
            remSleepMinutes: 0,
            lightSleepMinutes: 0,
            awakeMinutes: 0,
            sleepEfficiency: 0,
            bedtime: nil,
            wakeTime: nil
        )
    }

    func fetchWorkouts(for date: Date) async throws -> [WorkoutSample] {
        // Step 5.5: Real implementation
        Logger.healthkit.debug("fetchWorkouts called — stub returning empty")
        return []
    }

    // MARK: - Write Methods (Stubs — Implemented in Step 5.7)

    func writeWorkout(_ workout: WorkoutSample) async throws {
        // Step 5.7: Real implementation
        Logger.healthkit.debug("writeWorkout called — stub, no-op")
    }

    func writeNutrition(_ nutrition: NutritionSample) async throws {
        // Step 5.7: Real implementation
        Logger.healthkit.debug("writeNutrition called — stub, no-op")
    }

    // MARK: - Background Delivery (Stub — Implemented in Step 5.6)

    func enableBackgroundDelivery() async throws {
        // Step 5.6: Real implementation
        Logger.healthkit.debug("enableBackgroundDelivery called — stub, no-op")
    }
}
