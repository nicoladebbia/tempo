import Foundation

final class MockHealthKitService: HealthKitServiceProtocol, @unchecked Sendable {

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

    func writeWorkout(_ workout: WorkoutSample) async throws {
        // No-op in mock
    }

    func writeNutrition(_ nutrition: NutritionSample) async throws {
        // No-op in mock
    }

    func enableBackgroundDelivery() async throws {
        // No-op in mock
    }
}
