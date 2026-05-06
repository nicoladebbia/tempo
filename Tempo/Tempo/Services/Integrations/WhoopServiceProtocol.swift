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
    var isDemoMode: Bool { get }
    var hasCredentials: Bool { get }
    var lastSyncDate: Date? { get }
    func connect() async throws
    func connectDemo() async
    func disconnect() async throws
    func saveCredentials(clientID: String, clientSecret: String) throws
    func clearCredentials() throws
    func fetchRecovery(for date: Date) async throws -> WhoopRecoveryData
    func fetchRecoveryBatch(for date: Date) async throws -> [WhoopRecoveryData]
    func fetchSleepBatch(for date: Date) async throws -> [WhoopSleepData]
    func fetchSleep(for date: Date) async throws -> WhoopSleepData
    func fetchWorkouts(for date: Date) async throws -> [WhoopWorkoutData]
    func fetchCycle(for date: Date) async throws -> WhoopCycleData
    func syncAll() async throws
    func checkConnectionOnLaunch() async

    /// Refresh the Whoop access token if it expires within 60s. No-op when fresh.
    /// Used on scenePhase==.active and cold launch.
    /// Retries once on transient network errors; throws on terminal 4xx responses.
    func refreshIfNeeded() async throws
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
