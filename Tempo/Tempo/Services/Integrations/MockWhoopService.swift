//
// MockWhoopService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

@Observable
final class MockWhoopService: WhoopServiceProtocol, @unchecked Sendable {
    private(set) var connectionState: WhoopConnectionState = .connected
    private(set) var isDemoMode: Bool = true
    var hasCredentials: Bool {
        true
    }

    private(set) var lastSyncDate: Date? = Date()

    func connect() async throws {
        connectionState = .connecting
        try await Task.sleep(for: .milliseconds(500))
        connectionState = .connected
    }

    func connectDemo() async {
        connectionState = .connected
    }

    func disconnect() async throws {
        connectionState = .disconnected
    }

    func saveCredentials(clientID: String, clientSecret: String) throws {}
    func clearCredentials() throws {}

    /// Yellow zone recovery day
    func fetchRecovery(for date: Date) async throws -> WhoopRecoveryData {
        WhoopRecoveryData(
            score: 72.0,
            hrvRmssd: 48.0,
            restingHeartRate: 62.0,
            spo2: 97.5,
            skinTemp: 33.2,
            date: date
        )
    }

    func fetchRecoveryBatch(for date: Date) async throws -> [WhoopRecoveryData] {
        try await [fetchRecovery(for: date)]
    }

    func fetchSleepBatch(for date: Date) async throws -> [WhoopSleepData] {
        try await [fetchSleep(for: date)]
    }

    func fetchSleep(for date: Date) async throws -> WhoopSleepData {
        WhoopSleepData(
            totalHours: 7.2,
            sleepScore: 78.0,
            sleepEfficiency: 85.0,
            sleepConsistency: 72.0,
            deepSleepMinutes: 75,
            remSleepMinutes: 88,
            lightSleepMinutes: 195,
            awakeMinutes: 22,
            respiratoryRate: 15.2,
            date: date
        )
    }

    func fetchWorkouts(for date: Date) async throws -> [WhoopWorkoutData] {
        [
            WhoopWorkoutData(
                strain: 12.4,
                averageHeartRate: 135,
                maxHeartRate: 172,
                caloriesBurned: 480,
                durationMinutes: 62,
                sportID: 1,
                startTime: date.addingTimeInterval(-7200)
            ),
        ]
    }

    func fetchCycle(for date: Date) async throws -> WhoopCycleData {
        WhoopCycleData(
            strain: 12.4,
            averageHeartRate: 78,
            maxHeartRate: 172,
            caloriesBurned: 2340,
            dayStrain: 12.4,
            date: date
        )
    }

    func syncAll() async throws {
        // No-op in mock
    }

    func checkConnectionOnLaunch() async {
        // Already connected in mock
    }

    func refreshIfNeeded() async throws {
        // No-op: mock has no real tokens.
    }
}
