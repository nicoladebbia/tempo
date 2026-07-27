//
// RunImporterTests.swift
// Tempo
//
// §13 — pins the HealthKit→RunSession mirror: only runs import, GPS blips
// are rejected, pace derives from distance+duration, and the upsert is
// idempotent per start date (re-imports never duplicate history).
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class RunImporterTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RunSession.self, configurations: config)
        return ModelContext(container)
    }

    private func runSample(
        start: Date = Date(timeIntervalSince1970: 1_750_000_000),
        minutes: Double = 30,
        meters: Double? = 5000,
        type: String = "run"
    ) -> WorkoutSample {
        WorkoutSample(
            startDate: start,
            endDate: start.addingTimeInterval(minutes * 60),
            workoutType: type,
            durationMinutes: minutes,
            activeCalories: 320,
            averageHeartRate: 155,
            maxHeartRate: 176,
            distanceMeters: meters
        )
    }

    func testMapsRunWithDerivedPace() {
        let run = RunImporter.runSession(from: runSample())
        XCTAssertNotNil(run)
        XCTAssertEqual(run?.distanceMeters, 5000)
        XCTAssertEqual(run?.durationSeconds, 1800)
        // 1800s over 5km → 360 s/km (6:00 pace).
        XCTAssertEqual(run?.avgPaceSecondsPerKm ?? 0, 360, accuracy: 0.5)
        XCTAssertEqual(run?.avgHR, 155)
    }

    func testRejectsNonRunsAndBlips() {
        XCTAssertNil(RunImporter.runSession(from: runSample(type: "strength")),
                     "Only running workouts mirror into run history")
        XCTAssertNil(RunImporter.runSession(from: runSample(meters: 40)),
                     "Sub-100m GPS blips are not runs")
        XCTAssertNil(RunImporter.runSession(from: runSample(meters: nil)),
                     "Distance-less rows don't import")
    }

    func testUpsertIsIdempotentPerStartDate() throws {
        let context = try makeContext()
        let sample = runSample()

        XCTAssertTrue(RunImporter.upsert(sample, modelContext: context), "First import inserts")
        XCTAssertFalse(RunImporter.upsert(sample, modelContext: context), "Re-import skips")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RunSession>()), 1)

        let other = runSample(start: Date(timeIntervalSince1970: 1_750_100_000))
        XCTAssertTrue(RunImporter.upsert(other, modelContext: context), "A different run inserts")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RunSession>()), 2)
    }
}
