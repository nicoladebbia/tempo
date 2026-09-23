//
// WhoopServiceProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - WhoopConnectionState

enum WhoopConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - WhoopServiceProtocol

extension WhoopServiceProtocol {
    /// Connected to a REAL Whoop account. Demo mode is display-only: anything
    /// that persists or plans off Whoop data (DailyRecovery rows, backfill,
    /// meal-plan anchors, non-gym completions) must check this, never
    /// `connectionState` alone, or mock numbers get saved as the user's own.
    var providesRealData: Bool {
        connectionState == .connected && !isDemoMode
    }
}

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
    func fetchRecoveryBatch(start: Date, end: Date) async throws -> [WhoopRecoveryData]
    func fetchSleepBatch(start: Date, end: Date) async throws -> [WhoopSleepData]
    func fetchSleep(for date: Date) async throws -> WhoopSleepData
    func fetchWorkouts(for date: Date) async throws -> [WhoopWorkoutData]
    func fetchCycle(for date: Date) async throws -> WhoopCycleData
    /// Fetch every scored physiological cycle whose start falls in
    /// `[start, end]`. Used to average daily energy expenditure over a window
    /// (e.g. 7-day TDEE) so a single lazy/rest day can't drag the estimate
    /// down — feeding one day's burn as the "average" is a known failure mode.
    func fetchCycleBatch(start: Date, end: Date) async throws -> [WhoopCycleData]

    /// Cached 7-day rolling average of daily energy expenditure (kcal), or nil
    /// until `ensureWeeklyTDEEAverage()` has populated it (or when Whoop is
    /// disconnected / the fetch failed). Lives on the SHARED WhoopService so
    /// every surface (Nutrition Today + Dashboard Fuel) reads ONE number and
    /// they can never disagree on the no-plan TDEE estimate — a VM-local cache
    /// would desync the two surfaces.
    var weeklyTDEEAverage: Double? { get }

    /// Compute and cache `weeklyTDEEAverage` from the last 7 cycles. Idempotent
    /// and cheap to call from any surface's load path; one ranged /cycle call
    /// over already-synced data. Safe to await repeatedly — it just refreshes
    /// the cached value. Never throws: failures leave the cache nil and are
    /// logged, so callers don't need a do/catch around it.
    func ensureWeeklyTDEEAverage() async
    func syncAll() async throws
    func checkConnectionOnLaunch() async

    /// Refresh the Whoop access token if it expires within 60s. No-op when fresh.
    /// Used on scenePhase==.active and cold launch.
    /// Retries once on transient network errors; throws on terminal 4xx responses.
    func refreshIfNeeded() async throws

    /// Drops all in-memory cached fetch responses so the next call hits the
    /// network. Use from explicit user-driven refresh paths (pull-to-refresh).
    /// No-op when nothing is cached.
    func invalidateCache() async
}

// MARK: - WhoopRecoveryData

struct WhoopRecoveryData: Sendable {
    let score: Double
    let hrvRmssd: Double
    let restingHeartRate: Double
    let spo2: Double?
    let skinTemp: Double?
    let date: Date
}

// MARK: - WhoopSleepData

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
    /// When the user fell asleep / woke, parsed from the Whoop record's
    /// start/end. Nil for batch fallbacks that don't carry them. Used as
    /// the meal-timing anchor (the user's real rhythm) since iOS doesn't
    /// expose the Health Sleep Schedule to apps.
    var bedtime: Date? = nil
    var wakeTime: Date? = nil
}

// MARK: - WhoopWorkoutData

struct WhoopWorkoutData: Sendable {
    let strain: Double
    let averageHeartRate: Double
    let maxHeartRate: Double
    let caloriesBurned: Double
    let durationMinutes: Double
    let sportID: Int
    let startTime: Date
}

// MARK: - WhoopCycleData

struct WhoopCycleData: Sendable {
    let strain: Double
    let averageHeartRate: Double
    let maxHeartRate: Double
    let caloriesBurned: Double
    let dayStrain: Double
    let date: Date
}
