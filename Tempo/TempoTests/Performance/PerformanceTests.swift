import SwiftData
import XCTest
@testable import Tempo

// MARK: - Performance Tests
// Per BUILD_PLAN Step 19.5 — Measures SwiftData fetch performance and view-model operations.

final class PerformanceTests: XCTestCase {

    // MARK: - SwiftData Fetch Performance

    @MainActor
    func testSnapshotFetchPerformance() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Seed 365 daily snapshots (1 year)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for i in 0..<365 {
            let date = cal.date(byAdding: .day, value: -i, to: today)!
            let snapshot = makeSnapshot(date: date, recoveryScore: Double.random(in: 30...100))
            context.insert(snapshot)
        }
        try context.save()

        measure {
            let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: today)!
            let descriptor = FetchDescriptor<DailySnapshot>(
                predicate: #Predicate { $0.date >= thirtyDaysAgo },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let results = try? context.fetch(descriptor)
            XCTAssertNotNil(results)
            XCTAssertEqual(results?.count, 30)
        }
    }

    @MainActor
    func testAccountabilityFetchPerformance() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Seed 365 daily accountability records
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for i in 0..<365 {
            let date = cal.date(byAdding: .day, value: -i, to: today)!
            let acct = makeAccountability(
                date: date,
                leisureUnlocked: Bool.random(),
                totalStudyMinutes: Int.random(in: 0...240),
                accountabilityScore: Int.random(in: 0...100)
            )
            context.insert(acct)
        }
        try context.save()

        measure {
            let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: today)!
            let descriptor = FetchDescriptor<DailyAccountability>(
                predicate: #Predicate { $0.date >= sevenDaysAgo },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let results = try? context.fetch(descriptor)
            XCTAssertNotNil(results)
            XCTAssertEqual(results?.count, 7)
        }
    }

    @MainActor
    func testXPEventFetchPerformance() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Seed 1000 XP events
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for i in 0..<1000 {
            let date = cal.date(byAdding: .hour, value: -i, to: today)!
            let event = XPEvent(
                source: .workout,
                amount: Int.random(in: 10...100),
                date: date,
                detail: "Test event \(i)"
            )
            context.insert(event)
        }
        try context.save()

        measure {
            let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: today)!
            let descriptor = FetchDescriptor<XPEvent>(
                predicate: #Predicate { $0.date >= thirtyDaysAgo },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let results = try? context.fetch(descriptor)
            XCTAssertNotNil(results)
        }
    }

    // MARK: - Engine Computation Performance

    func testScoringEnginePerformance() {
        let engine = ScoringEngine()
        measure {
            for _ in 0..<100 {
                _ = engine.calculateDailyScore(
                    nnCompleted: 3,
                    nnTotal: 5,
                    workoutCompleted: true,
                    strain: 14.5,
                    mealsLogged: 3,
                    mealsPlanned: 3,
                    calorieCompliance: 0.95,
                    proteinCompliance: 0.9,
                    recoveryScore: 80,
                    sleepScore: 75,
                    steps: 12000,
                    activeCalories: 650
                )
            }
        }
    }

    func testXPEngineLevelCalculationPerformance() {
        let engine = XPEngine()
        measure {
            for xp in stride(from: 0, to: 100000, by: 100) {
                _ = engine.level(for: xp)
                _ = engine.xpToNextLevel(currentXP: xp)
                _ = engine.levelProgress(currentXP: xp)
            }
        }
    }
}
