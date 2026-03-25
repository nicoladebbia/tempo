import SwiftData
import XCTest
@testable import Tempo

// MARK: - SwiftData Test Helper
// Per BUILD_PLAN Step 19.3 — Provides in-memory SwiftData container for unit tests.

extension XCTestCase {

    /// Creates an in-memory ModelContainer for testing with all Tempo models.
    @MainActor
    func makeTestContainer() throws -> ModelContainer {
        let schema = Schema([
            DailySnapshot.self,
            DailyAccountability.self,
            NonNegotiableProgress.self,
            NonNegotiable.self,
            StudySession.self,
            XPEvent.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Creates a basic DailySnapshot with sensible defaults for testing.
    @MainActor
    func makeSnapshot(
        date: Date = Date(),
        recoveryScore: Double? = nil,
        sleepScore: Double? = nil,
        sleepHours: Double? = nil,
        strain: Double? = nil,
        caloriesConsumed: Int? = nil,
        calorieTarget: Int? = nil,
        proteinActual: Double? = nil,
        proteinTarget: Double? = nil,
        mealsLogged: Int = 0,
        mealsPlanned: Int = 0,
        studyMinutes: Int = 0,
        studyTarget: Int = 0,
        steps: Int? = nil,
        activeCalories: Double? = nil,
        workoutCompleted: Bool = false
    ) -> DailySnapshot {
        let snapshot = DailySnapshot(
            date: date,
            mealsLogged: mealsLogged,
            mealsPlanned: mealsPlanned,
            studyMinutes: studyMinutes,
            studyTarget: studyTarget
        )
        snapshot.recoveryScore = recoveryScore
        snapshot.sleepScore = sleepScore
        snapshot.sleepHours = sleepHours
        snapshot.strain = strain
        snapshot.caloriesConsumed = caloriesConsumed
        snapshot.calorieTarget = calorieTarget
        snapshot.proteinActual = proteinActual
        snapshot.proteinTarget = proteinTarget
        snapshot.steps = steps
        snapshot.activeCalories = activeCalories
        snapshot.workoutCompleted = workoutCompleted
        return snapshot
    }

    /// Creates a basic DailyAccountability for testing.
    @MainActor
    func makeAccountability(
        date: Date = Date(),
        leisureUnlocked: Bool = false,
        unlockedAt: Date? = nil,
        totalStudyMinutes: Int = 0,
        accountabilityScore: Int = 0
    ) -> DailyAccountability {
        DailyAccountability(
            date: date,
            leisureUnlocked: leisureUnlocked,
            unlockedAt: unlockedAt,
            totalStudyMinutes: totalStudyMinutes,
            accountabilityScore: accountabilityScore
        )
    }
}
