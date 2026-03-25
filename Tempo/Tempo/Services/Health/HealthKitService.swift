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

    // MARK: - Fetch Heart Rate + HRV + RHR
    // Per INTEGRATION_SPECS.md Section 2.2.2 — Heart rate samples, HRV (SDNN), RHR.
    // Per TECHNICAL_FEASIBILITY_AUDIT.md Section 1.1/1.5:
    //   - RHR only available from Apple Watch (nil otherwise)
    //   - Live HR during workouts requires Apple Watch
    //   - Always prefer Whoop API data for HRV/RHR when available

    func fetchHeartRate(for date: Date) async throws -> [HeartRateSample] {
        let hrType = HKQuantityType(.heartRate)
        let (startOfDay, endOfDay) = dayBounds(for: date)
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )

        let samples = try await descriptor.result(for: healthStore)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        let result = samples.map { sample in
            HeartRateSample(
                timestamp: sample.startDate,
                bpm: sample.quantity.doubleValue(for: bpmUnit)
            )
        }
        Logger.healthkit.debug("fetchHeartRate: \(result.count) samples for \(date)")
        return result
    }

    func fetchHRV(for date: Date) async throws -> Double? {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let (startOfDay, endOfDay) = dayBounds(for: date)
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrvType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )

        let samples = try await descriptor.result(for: healthStore)
        guard let latest = samples.first else {
            Logger.healthkit.debug("fetchHRV: no data for \(date)")
            return nil
        }

        let sdnn = latest.quantity.doubleValue(for: .secondUnit(with: .milli))
        Logger.healthkit.debug("fetchHRV: \(String(format: "%.1f", sdnn))ms for \(date)")
        return sdnn
    }

    func fetchRestingHeartRate(for date: Date) async throws -> Double? {
        // Per TECHNICAL_FEASIBILITY_AUDIT.md Section 1.1:
        // RHR only written by Apple Watch. Returns nil if no Apple Watch.
        let rhrType = HKQuantityType(.restingHeartRate)
        let (startOfDay, endOfDay) = dayBounds(for: date)
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: rhrType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )

        let samples = try await descriptor.result(for: healthStore)
        guard let latest = samples.first else {
            Logger.healthkit.debug("fetchRestingHeartRate: no data for \(date) (expected without Apple Watch)")
            return nil
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let rhr = latest.quantity.doubleValue(for: bpmUnit)
        Logger.healthkit.debug("fetchRestingHeartRate: \(String(format: "%.0f", rhr)) bpm for \(date)")
        return rhr
    }

    // MARK: - Fetch Sleep Analysis
    // Per INTEGRATION_SPECS.md Section 2.2.3 — Sleep stage parsing.
    // Search window: 6 PM yesterday → 12 PM today (sleep crosses midnight).
    // Handles both iOS 16+ granular stages and legacy .asleep/.inBed format.

    func fetchSleepAnalysis(for date: Date) async throws -> SleepData {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let calendar = Calendar.current

        // Sleep window: 6 PM previous evening to 12 PM target date
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date)!
        let sixPMYesterday = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday)!
        let noonToday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!

        let predicate = HKQuery.predicateForSamples(
            withStart: sixPMYesterday,
            end: noonToday,
            options: .strictStartDate
        )

        let samples = try await fetchCategorySamples(
            type: sleepType,
            predicate: predicate
        )

        guard !samples.isEmpty else {
            Logger.healthkit.debug("fetchSleepAnalysis: no sleep data for \(date)")
            return SleepData(
                totalHours: 0, deepSleepMinutes: 0, remSleepMinutes: 0,
                lightSleepMinutes: 0, awakeMinutes: 0, sleepEfficiency: 0,
                bedtime: nil, wakeTime: nil
            )
        }

        // Group by source to handle overlapping samples from multiple apps
        let grouped = Dictionary(grouping: samples) { $0.sourceRevision.source.bundleIdentifier }
        let preferredSamples = selectPreferredSleepSource(grouped)

        // Parse sleep stages
        var totalInBed: TimeInterval = 0
        var totalAsleep: TimeInterval = 0
        var deepSleep: TimeInterval = 0
        var remSleep: TimeInterval = 0
        var coreSleep: TimeInterval = 0
        var awake: TimeInterval = 0

        for sample in preferredSamples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)

            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .inBed:
                totalInBed += duration
            case .asleepUnspecified:
                totalAsleep += duration
            case .asleepCore:
                coreSleep += duration
                totalAsleep += duration
            case .asleepDeep:
                deepSleep += duration
                totalAsleep += duration
            case .asleepREM:
                remSleep += duration
                totalAsleep += duration
            case .awake:
                awake += duration
            default:
                break
            }
        }

        // If no stage detail, count all asleep as light sleep
        let lightMinutes: Int
        if deepSleep == 0 && remSleep == 0 && coreSleep == 0 && totalAsleep > 0 {
            // Legacy format: all sleep counted as light/unspecified
            lightMinutes = Int(totalAsleep / 60)
        } else {
            // Granular stages: core sleep maps to light
            lightMinutes = Int(coreSleep / 60)
        }

        let totalHours = totalAsleep / 3600
        let totalInBedTime = max(totalInBed, totalAsleep + awake)
        let efficiency = totalInBedTime > 0 ? (totalAsleep / totalInBedTime) * 100 : 0

        let bedtime = preferredSamples.first?.startDate
        let wakeTime = preferredSamples.last?.endDate

        Logger.healthkit.debug("fetchSleepAnalysis: \(String(format: "%.1f", totalHours))h total, efficiency \(String(format: "%.0f", efficiency))%")

        return SleepData(
            totalHours: totalHours,
            deepSleepMinutes: Int(deepSleep / 60),
            remSleepMinutes: Int(remSleep / 60),
            lightSleepMinutes: lightMinutes,
            awakeMinutes: Int(awake / 60),
            sleepEfficiency: efficiency,
            bedtime: bedtime,
            wakeTime: wakeTime
        )
    }

    // MARK: - Sleep Source Priority
    // Per INTEGRATION_SPECS.md Section 2.2.3 — Priority: Whoop > Apple Watch > iPhone > Other

    private func selectPreferredSleepSource(
        _ grouped: [String?: [HKCategorySample]]
    ) -> [HKCategorySample] {
        let priorityOrder = [
            "com.whoop.Diamond",
            "com.apple.health",
        ]

        for bundlePrefix in priorityOrder {
            if let match = grouped.first(where: { ($0.key ?? "").hasPrefix(bundlePrefix) }) {
                return match.value.sorted { $0.startDate < $1.startDate }
            }
        }

        // Fall back to source with most samples
        let best = grouped.max { $0.value.count < $1.value.count }
        return (best?.value ?? []).sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Category Sample Query Helper

    private func fetchCategorySamples(
        type: HKCategoryType,
        predicate: NSPredicate
    ) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
                }
            }
            healthStore.execute(query)
        }
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
