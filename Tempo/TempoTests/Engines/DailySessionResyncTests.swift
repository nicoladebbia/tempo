//
// DailySessionResyncTests.swift
// Tempo
//
// Pins the §11.14 fix for the FOOTBALL-header + UPPER-card contradiction
// (device screenshot 2026-07-29). A schedule edit re-resolves today's
// WorkoutPlan row, but the day-key-cached DailySession survived until
// midnight — the header said FOOTBALL while the coach card still prescribed
// the morning's UPPER day. invalidateStaleDailySession drops the stale
// session and clears the day-key so the coach re-runs (deterministic/free)
// and the card can never contradict the day it sits under.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class DailySessionResyncTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutPlan.self,
            Exercise.self,
            ExerciseHistory.self,
            PlannedExercise.self,
            PlannedSet.self,
            PredictionLog.self,
            AdaptiveProfile.self,
            UserSettings.self,
            UserProfile.self,
            BodyComposition.self,
            SetFeedback.self,
            Match.self,
            ActivitySession.self,
            DailySession.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    private func insertSession(_ context: ModelContext, modality: String, plan: WorkoutPlan? = nil) -> DailySession {
        let session = DailySession(
            date: Date(),
            modality: modality,
            intensity: .moderate,
            durationMin: 60,
            blocksJSON: "[]",
            shortWhy: "Lift, then an easy pool",
            floorTier: .normal,
            wasDowngraded: false,
            source: .simple,
            workoutPlan: plan
        )
        context.insert(session)
        try? context.save()
        return session
    }

    private func sessionCount(_ context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<DailySession>())) ?? -1
    }

    func testMismatchedSessionOnPlannedDayIsInvalidated() throws {
        // The device case: session says upper, the (re-resolved) plan row says
        // football → the session is stale and must go, day-key cleared so the
        // coach re-runs.
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .football)
        context.insert(plan)
        _ = insertSession(context, modality: "upper", plan: plan)

        let profile = vm.fetchOrCreateAdaptiveProfile(modelContext: context)
        profile.lastDailySessionDayKey = "2026-07-29"
        try context.save()

        let invalidated = vm.invalidateStaleDailySession(for: plan, modelContext: context)
        XCTAssertTrue(invalidated, "upper session on a football plan is stale")
        XCTAssertEqual(sessionCount(context), 0, "Stale session row is deleted")
        XCTAssertNil(profile.lastDailySessionDayKey, "Day-key cleared so the coach re-runs")
        XCTAssertNil(vm.dailySession, "In-memory card cleared too")
    }

    func testMatchingSessionIsLeftAlone() throws {
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .upper)
        context.insert(plan)
        _ = insertSession(context, modality: "upper", plan: plan)

        let profile = vm.fetchOrCreateAdaptiveProfile(modelContext: context)
        profile.lastDailySessionDayKey = "2026-07-29"
        try context.save()

        let invalidated = vm.invalidateStaleDailySession(for: plan, modelContext: context)
        XCTAssertFalse(invalidated, "Matching modality is not stale")
        XCTAssertEqual(sessionCount(context), 1, "Session untouched")
        XCTAssertEqual(profile.lastDailySessionDayKey, "2026-07-29", "Day-key untouched")
    }

    func testCompletedDayIsNeverResynced() throws {
        // Sacredness: once the day is done (or in progress), the record stands —
        // a late schedule edit must not delete the card that describes what
        // actually happened.
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .football)
        plan.status = .completed
        context.insert(plan)
        _ = insertSession(context, modality: "upper", plan: plan)
        try context.save()

        let invalidated = vm.invalidateStaleDailySession(for: plan, modelContext: context)
        XCTAssertFalse(invalidated, "Completed day is sacred")
        XCTAssertEqual(sessionCount(context), 1, "Session untouched on a terminal day")
    }

    func testUnmappableModalityIsLeftAlone() throws {
        // A modality label that doesn't map to a plan type can't contradict the
        // row (the §8 reshape never moved the row for it either) — leave it.
        let context = try makeContext()
        let vm = makeVM()
        let plan = WorkoutPlan(date: Date(), type: .football)
        context.insert(plan)
        _ = insertSession(context, modality: "breathwork", plan: plan)
        try context.save()

        let invalidated = vm.invalidateStaleDailySession(for: plan, modelContext: context)
        XCTAssertFalse(invalidated, "Unmappable modality is not evidence of desync")
        XCTAssertEqual(sessionCount(context), 1)
    }
}
