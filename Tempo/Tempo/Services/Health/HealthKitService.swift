//
// HealthKitService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import HealthKit
import os
import UIKit

// MARK: - HealthKit Service (Real Implementation)

// Per INTEGRATION_SPECS.md Section 2.1 — Real HKHealthStore implementation.
// Per BUILD_PLAN.md Step 5.1 — Authorization flow, partial handling, logging.
// Fetch/write methods are stubs (implemented in steps 5.2-5.7).

final class HealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    // MARK: - Properties

    let healthStore = HKHealthStore()

    /// Current authorization result. Updated on authorization and on every foreground check.
    private(set) var authResult: HealthKitAuthResult = .unavailable

    /// Tracks previous write status for revocation detection.
    /// Per INTEGRATION_SPECS.md Section 2.1 — detect permission revocation on app launch.
    private var previousWriteStatus: HKAuthorizationStatus = .notDetermined

    /// In-flight guard for the one-time calories/distance permission sheet.
    private var isRequestingNewWriteTypes = false

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
            // Single source of truth for the dashboard gating flag. Driven
            // here on user-initiated request, and from verifyPermissionsOnLaunch
            // when a prior install's authorization is detected via read probe.
            UserDefaults.standard.set(true, forKey: "healthKitAuthorized")
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
        if workoutStatus == .sharingDenied, previousWriteStatus == .sharingAuthorized {
            Logger.healthkit.warning("HealthKit write permission revoked by user")
            authResult = .denied
        }
        previousWriteStatus = workoutStatus

        // Users who allowed workout writes before calories/distance were added
        // get one Health sheet for just the new types (iOS never re-asks a
        // type that's already been decided).
        if workoutStatus == .sharingAuthorized, !isRequestingNewWriteTypes {
            let newTypes = HealthKitConstants.writeTypes.filter {
                healthStore.authorizationStatus(for: $0) == .notDetermined
            }
            if !newTypes.isEmpty {
                // Runs on every foreground — never stack a second sheet.
                isRequestingNewWriteTypes = true
                defer { isRequestingNewWriteTypes = false }
                do {
                    try await healthStore.requestAuthorization(toShare: newTypes, read: [])
                } catch {
                    Logger.healthkit.error("New write types request failed: \(error.localizedDescription)")
                }
            }
        }

        // Update full write status
        if case .denied = authResult {} else {
            authResult = checkWriteAuthorizationStatus()
        }

        // Attempt a lightweight read query to detect read permission revocation.
        // Per INTEGRATION_SPECS.md: read permission revocation is not directly queryable.
        // If the probe succeeds, treat the user as authorized for read so the
        // dashboard doesn't show "Authorize Health" after a reinstall when iOS
        // already has prior permission for this account.
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
            UserDefaults.standard.set(true, forKey: "healthKitAuthorized")
        } catch {
            Logger.healthkit.debug("HealthKit read query failed on launch: \(error.localizedDescription)")
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

    /// Short-lived cache for fetchSleepAnalysis so MealDetailView /
    /// DashboardViewModel / FuelDayScheduleViewModel don't each fire a
    /// fresh HealthKit query in the same 60-second window. Keyed by
    /// the startOfDay of the requested date — overnight sleep is the
    /// same regardless of when in the day you ask.
    /// Uses OSAllocatedUnfairLock (iOS 16+) since NSLock is unavailable
    /// from async contexts under strict concurrency.
    private static let sleepCacheTTL: TimeInterval = 60
    private static let sleepCache = OSAllocatedUnfairLock<[Date: (SleepData, Date)]>(initialState: [:])

    func fetchSleepAnalysis(for date: Date) async throws -> SleepData {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let calendar = Calendar.current

        // Cache lookup keyed by calendar-day. A 60s TTL is enough to
        // absorb rapid tab-switch / view-remount churn without serving
        // stale data when the user actually wakes mid-day.
        let cacheKey = calendar.startOfDay(for: date)
        if let cached = Self.sleepCache.withLock({ cache -> SleepData? in
            guard let (value, ts) = cache[cacheKey],
                  Date().timeIntervalSince(ts) < Self.sleepCacheTTL
            else { return nil }
            return value
        }) {
            return cached
        }

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
            let empty = SleepData(
                totalHours: 0, deepSleepMinutes: 0, remSleepMinutes: 0,
                lightSleepMinutes: 0, awakeMinutes: 0, sleepEfficiency: 0,
                bedtime: nil, wakeTime: nil
            )
            Self.sleepCache.withLock { $0[cacheKey] = (empty, Date()) }
            return empty
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
        let lightMinutes = if deepSleep == 0 && remSleep == 0 && coreSleep == 0 && totalAsleep > 0 {
            // Legacy format: all sleep counted as light/unspecified
            Int(totalAsleep / 60)
        } else {
            // Granular stages: core sleep maps to light
            Int(coreSleep / 60)
        }

        let totalHours = totalAsleep / 3600
        let totalInBedTime = max(totalInBed, totalAsleep + awake)
        let efficiency = totalInBedTime > 0 ? (totalAsleep / totalInBedTime) * 100 : 0

        let bedtime = preferredSamples.first?.startDate
        let wakeTime = preferredSamples.last?.endDate

        Logger.healthkit
            .debug("fetchSleepAnalysis: \(String(format: "%.1f", totalHours))h total, efficiency \(String(format: "%.0f", efficiency))%")

        let result = SleepData(
            totalHours: totalHours,
            deepSleepMinutes: Int(deepSleep / 60),
            remSleepMinutes: Int(remSleep / 60),
            lightSleepMinutes: lightMinutes,
            awakeMinutes: Int(awake / 60),
            sleepEfficiency: efficiency,
            bedtime: bedtime,
            wakeTime: wakeTime
        )
        Self.sleepCache.withLock { $0[cacheKey] = (result, Date()) }
        return result
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

    // MARK: - Fetch Body Composition

    // Reads weight, body fat %, lean mass, and height from HealthKit.
    // Withings Body Comp scale syncs this data automatically via the Withings app.

    func fetchBodyComposition() async throws -> BodyCompositionData {
        let weight = await fetchLatestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
        let bodyFat = await fetchLatestQuantity(.bodyFatPercentage, unit: .percent())
        let leanMass = await fetchLatestQuantity(.leanBodyMass, unit: .gramUnit(with: .kilo))
        let height = await fetchLatestQuantity(.height, unit: .meterUnit(with: .centi))

        // Get the measurement date from the weight sample (most recent)
        let measurementDate = await fetchLatestSampleDate(.bodyMass)

        let result = BodyCompositionData(
            weightKg: weight,
            bodyFatPercent: bodyFat.map { $0 * 100 }, // HealthKit stores as 0.0-1.0
            leanMassKg: leanMass,
            heightCm: height,
            measurementDate: measurementDate
        )

        Logger.healthkit
            .debug(
                "fetchBodyComposition: weight=\(weight ?? -1)kg, bf=\(result.bodyFatPercent ?? -1)%, lean=\(leanMass ?? -1)kg, height=\(height ?? -1)cm"
            )
        return result
    }

    private func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let type = HKQuantityType(identifier)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatestSampleDate(_ identifier: HKQuantityTypeIdentifier) async -> Date? {
        let type = HKQuantityType(identifier)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first?.startDate)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Fetch Workouts

    // Per INTEGRATION_SPECS.md Section 2.2.4 — Fetch workouts from all sources.
    // Maps HKWorkoutActivityType to Tempo display format.

    func fetchWorkouts(for date: Date) async throws -> [WorkoutSample] {
        let workoutType = HKWorkoutType.workoutType()
        let (startOfDay, endOfDay) = dayBounds(for: date)
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            healthStore.execute(query)
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let results = workouts.map { workout in
            let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
            return WorkoutSample(
                startDate: workout.startDate,
                endDate: workout.endDate,
                workoutType: Self.mapActivityType(workout.workoutActivityType),
                durationMinutes: workout.duration / 60,
                activeCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                // Present for Watch-recorded workouts; nil otherwise.
                averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: bpm),
                maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: bpm),
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter())
            )
        }

        Logger.healthkit.debug("fetchWorkouts: \(results.count) workouts for \(date)")
        return results
    }

    // MARK: - Activity Type Mapping

    // Per INTEGRATION_SPECS.md Section 2.2.4 — Map HKWorkoutActivityType to Tempo display format.

    private static func mapActivityType(_ activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .traditionalStrengthTraining,
             .functionalStrengthTraining:
            "strength"
        case .running:
            "run"
        case .soccer:
            "football"
        case .cycling,
             .swimming,
             .rowing,
             .elliptical,
             .stairClimbing:
            "cardio"
        case .highIntensityIntervalTraining,
             .crossTraining:
            "hiit"
        case .yoga,
             .flexibility,
             .pilates,
             .mindAndBody:
            "mobility"
        case .walking,
             .hiking:
            "walk"
        case .basketball,
             .tennis,
             .tableTennis,
             .badminton,
             .rugby,
             .volleyball,
             .handball,
             .martialArts,
             .boxing:
            "sport"
        default:
            "other"
        }
    }

    // MARK: - Write Workout

    // Per INTEGRATION_SPECS.md Section 2.3.1 — Save completed RepForge workouts to HealthKit.
    // Uses HKWorkoutBuilder per spec. Checks for duplicate writes.

    func writeWorkout(_ workout: WorkoutSample) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            return
        }
        guard healthStore.authorizationStatus(for: HKWorkoutType.workoutType()) == .sharingAuthorized else {
            Logger.healthkit.warning("writeWorkout: not authorized to write workouts")
            return
        }

        // No duplicates: skip when any workout already in Health (a Watch
        // recording, another app, or our own earlier write) covers this span.
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: []
        )
        let existing: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: 20,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            healthStore.execute(query)
        }

        if HealthWorkoutDedupe.isDuplicate(
            start: workout.startDate,
            end: workout.endDate,
            existing: existing.map { ($0.startDate, $0.endDate) }
        ) {
            Logger.healthkit.debug("writeWorkout: overlapping workout already in Health, skipping")
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.mapStringToHKActivityType(workout.workoutType)
        configuration.locationType = workout.workoutType == "strength" ? .indoor : .unknown

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )

        try await builder.beginCollection(at: workout.startDate)

        if let volume = workout.totalVolumeKg, volume > 0 {
            try await builder.addMetadata(["TempoTotalVolumeKg": volume])
        }

        // Calories and distance only when their write permission is granted —
        // adding a sample of an unshared type throws and would lose the whole
        // workout (users who allowed workouts before these types existed).
        if workout.activeCalories > 0,
           healthStore.authorizationStatus(for: HKQuantityType(.activeEnergyBurned)) == .sharingAuthorized
        {
            let energySample = HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: workout.activeCalories),
                start: workout.startDate,
                end: workout.endDate
            )
            try await builder.addSamples([energySample])
        }

        if let distance = workout.distanceMeters, distance > 0,
           healthStore.authorizationStatus(for: HKQuantityType(.distanceWalkingRunning)) == .sharingAuthorized
        {
            let distanceSample = HKQuantitySample(
                type: HKQuantityType(.distanceWalkingRunning),
                quantity: HKQuantity(unit: .meter(), doubleValue: distance),
                start: workout.startDate,
                end: workout.endDate
            )
            try await builder.addSamples([distanceSample])
        }

        try await builder.endCollection(at: workout.endDate)
        try await builder.finishWorkout()

        Logger.healthkit
            .info(
                "writeWorkout: saved \(workout.workoutType) (\(String(format: "%.0f", workout.durationMinutes))m, \(String(format: "%.0f", workout.activeCalories)) cal)"
            )
    }

    // MARK: - Write Nutrition

    // Per INTEGRATION_SPECS.md Section 2.3.2 — Write nutrition as HKCorrelation.
    // Per TECHNICAL_FEASIBILITY_AUDIT.md Section 1.3 — use HKCorrelation for proper Health app display.

    func writeNutrition(_ nutrition: NutritionSample) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            return
        }
        guard healthStore.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) == .sharingAuthorized else {
            return // Silently skip — nutrition write is optional
        }

        var samples: [HKQuantitySample] = []

        samples.append(HKQuantitySample(
            type: HKQuantityType(.dietaryEnergyConsumed),
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: nutrition.calories),
            start: nutrition.date,
            end: nutrition.date
        ))

        samples.append(HKQuantitySample(
            type: HKQuantityType(.dietaryProtein),
            quantity: HKQuantity(unit: .gram(), doubleValue: nutrition.proteinGrams),
            start: nutrition.date,
            end: nutrition.date
        ))

        samples.append(HKQuantitySample(
            type: HKQuantityType(.dietaryCarbohydrates),
            quantity: HKQuantity(unit: .gram(), doubleValue: nutrition.carbsGrams),
            start: nutrition.date,
            end: nutrition.date
        ))

        samples.append(HKQuantitySample(
            type: HKQuantityType(.dietaryFatTotal),
            quantity: HKQuantity(unit: .gram(), doubleValue: nutrition.fatGrams),
            start: nutrition.date,
            end: nutrition.date
        ))

        // Wrap in HKCorrelation for proper Health app display
        let correlation = HKCorrelation(
            type: HKCorrelationType(.food),
            start: nutrition.date,
            end: nutrition.date,
            objects: Set(samples),
            metadata: ["TempoSource": "Tempo"]
        )

        try await healthStore.save(correlation)
        Logger.healthkit
            .info(
                "writeNutrition: saved \(String(format: "%.0f", nutrition.calories)) cal, P:\(String(format: "%.0f", nutrition.proteinGrams))g C:\(String(format: "%.0f", nutrition.carbsGrams))g F:\(String(format: "%.0f", nutrition.fatGrams))g"
            )
    }

    // MARK: - Reverse Activity Type Mapping

    static func mapStringToHKActivityType(_ type: String) -> HKWorkoutActivityType {
        switch type {
        case "strength": .traditionalStrengthTraining
        case "run", "running": .running
        case "football": .soccer
        case "cardio": .cycling
        case "hiit": .highIntensityIntervalTraining
        case "mobility": .flexibility
        case "walk": .walking
        case "sport": .other
        default: .other
        }
    }
}

// MARK: - HealthWorkoutDedupe

/// Pure overlap rule for Apple Health workout writes: a new workout is a
/// duplicate when an existing one overlaps it by at least 10 minutes or half
/// its length, whichever is smaller — so a Watch-recorded gym session (or our
/// own earlier write) blocks the copy, but a short walk that brushes the edge
/// doesn't.
enum HealthWorkoutDedupe {
    static func isDuplicate(start: Date, end: Date, existing: [(start: Date, end: Date)]) -> Bool {
        let length = max(1, end.timeIntervalSince(start))
        let threshold = min(600, length / 2)
        return existing.contains { other in
            let overlap = min(end, other.end).timeIntervalSince(max(start, other.start))
            return overlap >= threshold
        }
    }

    /// Gym session energy estimate: MET 3.5 × bodyweight (kg) × hours.
    /// 0 when bodyweight is unknown.
    static func strengthKcal(bodyweightKg: Double?, durationSeconds: Double) -> Double {
        guard let bodyweightKg, bodyweightKg > 0, durationSeconds > 0 else {
            return 0
        }
        return (3.5 * bodyweightKg * durationSeconds / 3600).rounded()
    }
}
