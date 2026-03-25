import Foundation

// MARK: - Connection State

enum WhoopConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - Protocol

protocol WhoopServiceProtocol: Sendable {
    var connectionState: WhoopConnectionState { get }
    func connect() async throws
    func disconnect() async throws
    func fetchRecovery(for date: Date) async throws -> WhoopRecoveryData
    func fetchSleep(for date: Date) async throws -> WhoopSleepData
    func fetchWorkouts(for date: Date) async throws -> [WhoopWorkoutData]
    func fetchCycle(for date: Date) async throws -> WhoopCycleData
    func syncAll() async throws
}

// MARK: - Data Types

struct WhoopRecoveryData: Sendable {
    let score: Double
    let hrvRmssd: Double
    let restingHeartRate: Double
    let spo2: Double?
    let skinTemp: Double?
    let date: Date
}

struct WhoopSleepData: Sendable {
    let totalHours: Double
    let sleepScore: Double
    let sleepEfficiency: Double
    let sleepConsistency: Double
    let deepSleepMinutes: Int
    let remSleepMinutes: Int
    let lightSleepMinutes: Int
    let awakeMinutes: Int
    let respiratoryRate: Double
    let date: Date
}

struct WhoopWorkoutData: Sendable {
    let strain: Double
    let averageHeartRate: Double
    let maxHeartRate: Double
    let caloriesBurned: Double
    let durationMinutes: Double
    let sportID: Int
    let startTime: Date
}

struct WhoopCycleData: Sendable {
    let strain: Double
    let averageHeartRate: Double
    let maxHeartRate: Double
    let caloriesBurned: Double
    let dayStrain: Double
    let date: Date
}
