//
// WhoopDemoDataCleanupTests.swift
// Tempo
//
// The one-shot purge must remove exactly the rows demo mode used to persist
// (MockWhoopService constants) and leave real data alone.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WhoopDemoDataCleanupTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try TempoModelContainer.create(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func recovery(score: Double, hrv: Double, rhr: Double, spo2: Double, skin: Double, daysAgo: Int = 0) -> DailyRecovery {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let row = DailyRecovery(date: date, recoveryScore: score, hrvRmssd: hrv, restingHR: rhr, spo2: spo2, skinTemp: skin)
        context.insert(row)
        return row
    }

    func testRemovesDemoRecoveryKeepsRealAndResetsBackfill() throws {
        _ = recovery(score: 72, hrv: 48, rhr: 62, spo2: 97.5, skin: 33.2)
        _ = recovery(score: 72, hrv: 51, rhr: 62, spo2: 97.5, skin: 33.2, daysAgo: 1) // real, one value differs
        let connection = WhoopConnection(isConnected: true)
        connection.didBackfill = true
        context.insert(connection)
        try context.save()

        let result = WhoopDemoDataCleanup.clean(context: context)
        try context.save()

        XCTAssertEqual(result.recoveries, 1)
        let remaining = try context.fetch(FetchDescriptor<DailyRecovery>())
        XCTAssertEqual(remaining.map(\.hrvRmssd), [51])
        XCTAssertFalse(connection.didBackfill)
    }

    func testRemovesMockSoccerSessionAndRevertsItsPlan() throws {
        let plan = WorkoutPlan(date: Date(), type: .football, status: .completed)
        context.insert(plan)
        context.insert(ActivitySession(
            date: Date(), startTime: Date(), workoutType: "football", sportID: 1, source: "whoop",
            workoutPlanID: plan.id, strain: 12.4, averageHeartRate: 135, maxHeartRate: 172,
            caloriesBurned: 480, durationMinutes: 62
        ))
        context.insert(ActivitySession(
            date: Date(), startTime: Date(), workoutType: "football", sportID: 1, source: "whoop",
            strain: 14.1, averageHeartRate: 150, caloriesBurned: 610, durationMinutes: 90
        ))
        try context.save()

        let result = WhoopDemoDataCleanup.clean(context: context)
        try context.save()

        XCTAssertEqual(result.activities, 1)
        XCTAssertEqual(result.plansReverted, 1)
        XCTAssertEqual(plan.status, .planned)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActivitySession>()).map(\.strain), [14.1])
    }

    func testNoDemoDataIsANoOp() throws {
        _ = recovery(score: 55, hrv: 40, rhr: 60, spo2: 96, skin: 33)
        let connection = WhoopConnection(isConnected: true)
        connection.didBackfill = true
        context.insert(connection)
        try context.save()

        XCTAssertEqual(WhoopDemoDataCleanup.clean(context: context), WhoopDemoDataCleanup.Result())
        XCTAssertTrue(connection.didBackfill)
    }

    func testDemoModeNeverCountsAsRealData() async {
        let mock = MockWhoopService() // connected + demo by default
        await mock.connectDemo()
        XCTAssertEqual(mock.connectionState, .connected)
        XCTAssertTrue(mock.isDemoMode)
        XCTAssertFalse(mock.providesRealData)
    }
}
