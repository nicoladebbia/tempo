//
// MockHealthKitService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

final class MockHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _writtenWorkouts: [WorkoutSample] = []
    private var _writtenNutrition: [NutritionSample] = []
    private var _deletedSyncIdentifiers: [String] = []
    private var _writtenWater: [(ml: Double, syncIdentifier: String)] = []
    private var _nutritionWritesSucceed = true

    /// Every workout handed to `writeWorkout`, in order (tests assert on this).
    var writtenWorkouts: [WorkoutSample] {
        lock.lock()
        defer { lock.unlock() }
        return _writtenWorkouts
    }

    func requestAuthorization() async throws {
        // No-op in mock
    }

    func fetchSteps(for date: Date) async throws -> Int {
        8432
    }

    func fetchActiveEnergy(for date: Date) async throws -> Double {
        342.0
    }

    func fetchHeartRate(for date: Date) async throws -> [HeartRateSample] {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: date)
        return (0 ..< 24).map { hour in
            HeartRateSample(
                timestamp: calendar.date(byAdding: .hour, value: hour, to: base) ?? base,
                bpm: Double.random(in: 58 ... 95)
            )
        }
    }

    func fetchHRV(for date: Date) async throws -> Double? {
        42.0
    }

    func fetchRestingHeartRate(for date: Date) async throws -> Double? {
        68.0
    }

    func fetchSleepAnalysis(for date: Date) async throws -> SleepData {
        let calendar = Calendar.current
        let bedtime = calendar.date(bySettingHour: 23, minute: 15, second: 0, of: date.addingTimeInterval(-86400))
        let wakeTime = calendar.date(bySettingHour: 6, minute: 45, second: 0, of: date)
        return SleepData(
            totalHours: 7.5,
            deepSleepMinutes: 82,
            remSleepMinutes: 95,
            lightSleepMinutes: 210,
            awakeMinutes: 18,
            sleepEfficiency: 88.0,
            bedtime: bedtime,
            wakeTime: wakeTime
        )
    }

    func fetchBodyComposition() async throws -> BodyCompositionData {
        BodyCompositionData(
            weightKg: 75.2,
            bodyFatPercent: 14.5,
            leanMassKg: 64.3,
            heightCm: 178,
            measurementDate: Date().addingTimeInterval(-3600)
        )
    }

    func fetchWorkouts(for date: Date) async throws -> [WorkoutSample] {
        [
            WorkoutSample(
                startDate: date.addingTimeInterval(-3600),
                endDate: date,
                workoutType: "traditionalStrengthTraining",
                durationMinutes: 55,
                activeCalories: 342,
                averageHeartRate: 128,
                maxHeartRate: 165,
                distanceMeters: nil
            ),
        ]
    }

    private func record(_ workout: WorkoutSample) {
        lock.withLock { _writtenWorkouts.append(workout) }
    }

    func writeWorkout(_ workout: WorkoutSample) async throws {
        record(workout)
    }

    /// Every nutrition sample handed to `writeNutrition`, in order.
    var writtenNutrition: [NutritionSample] {
        lock.withLock { _writtenNutrition }
    }

    /// Every sync identifier handed to `deleteNutrition`, in order.
    var deletedSyncIdentifiers: [String] {
        lock.withLock { _deletedSyncIdentifiers }
    }

    /// Every water write as (ml, syncIdentifier), in order.
    var writtenWater: [(ml: Double, syncIdentifier: String)] {
        lock.withLock { _writtenWater }
    }

    /// Set false to simulate "Health not authorised" (writes return false).
    var nutritionWritesSucceed: Bool {
        get { lock.withLock { _nutritionWritesSucceed } }
        set { lock.withLock { _nutritionWritesSucceed = newValue } }
    }

    @discardableResult
    func writeNutrition(_ nutrition: NutritionSample) async throws -> Bool {
        lock.withLock {
            if _nutritionWritesSucceed {
                _writtenNutrition.append(nutrition)
            }
            return _nutritionWritesSucceed
        }
    }

    func deleteNutrition(syncIdentifier: String) async throws {
        lock.withLock { _deletedSyncIdentifiers.append(syncIdentifier) }
    }

    @discardableResult
    func writeWater(ml: Double, date: Date, syncIdentifier: String) async throws -> Bool {
        lock.withLock {
            if _nutritionWritesSucceed {
                _writtenWater.append((ml, syncIdentifier))
            }
            return _nutritionWritesSucceed
        }
    }

    func enableBackgroundDelivery() async throws {
        // No-op in mock
    }
}
