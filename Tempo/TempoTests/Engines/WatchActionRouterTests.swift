//
// WatchActionRouterTests.swift
// Tempo
//
// Every watch action reaches its real phone operation, and unhandled or
// failed actions report false so the watch never fakes success.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class WatchActionRouterTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            DailyAccountability.self,
            NonNegotiable.self,
            NonNegotiableProgress.self,
            StudySession.self,
            Streak.self,
            PlannedMeal.self,
            WeeklyMealPlan.self,
            WorkoutPlan.self,
            Exercise.self,
            PlannedExercise.self,
            PlannedSet.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeRouter(configured context: ModelContext?) -> WatchActionRouter {
        let router = WatchActionRouter(
            accountabilityEngine: AccountabilityEngine(),
            notifications: MockNotificationService()
        )
        if let context {
            router.configure(modelContext: context)
        }
        return router
    }

    // MARK: - Unconfigured router fails closed

    func testUnconfiguredRouterAppliesNothing() {
        let router = makeRouter(configured: nil)
        XCTAssertFalse(router.handle(.init(action: .markNonNegotiableDone, payload: ["id": UUID().uuidString])))
        XCTAssertFalse(router.handle(.init(action: .markMealEaten, payload: ["id": UUID().uuidString])))
        XCTAssertFalse(router.handle(.init(action: .startWorkout, payload: [:])))
        XCTAssertFalse(router.handle(.init(action: .startFocusTimer, payload: [:])))
    }

    // MARK: - Non-Negotiables

    func testMarkNonNegotiableDoneCompletesTheRealProgressRow() throws {
        let context = try makeContext()
        let router = makeRouter(configured: context)

        let nn = NonNegotiable(name: "Train", type: .train, targetValue: 1)
        context.insert(nn)
        try context.save()

        let applied = router.handle(.init(action: .markNonNegotiableDone, payload: ["id": nn.id.uuidString]))
        XCTAssertTrue(applied)

        let progress = try XCTUnwrap(
            try context.fetch(FetchDescriptor<NonNegotiableProgress>()).first
        )
        XCTAssertEqual(progress.nonNegotiable?.id, nn.id)
        XCTAssertTrue(progress.isCompleted, "Same completion path as tapping the row in Lockdown")
    }

    func testMarkNonNegotiableDoneReturnsFalseForUnknownIDOrAlreadyDone() throws {
        let context = try makeContext()
        let router = makeRouter(configured: context)

        XCTAssertFalse(
            router.handle(.init(action: .markNonNegotiableDone, payload: ["id": UUID().uuidString])),
            "Unknown id — never fake success"
        )

        let nn = NonNegotiable(name: "Train", type: .train, targetValue: 1)
        context.insert(nn)
        try context.save()

        XCTAssertTrue(router.handle(.init(action: .markNonNegotiableDone, payload: ["id": nn.id.uuidString])))
        XCTAssertFalse(
            router.handle(.init(action: .markNonNegotiableDone, payload: ["id": nn.id.uuidString])),
            "Already completed — second tap is a no-op, not a re-fire"
        )
    }

    // MARK: - Meals

    func testMarkMealEatenMarksTheRealPlannedMeal() throws {
        let context = try makeContext()
        let router = makeRouter(configured: context)

        let meal = PlannedMeal(dayDate: Date(), mealName: "Lunch", status: .planned)
        context.insert(meal)
        try context.save()

        XCTAssertTrue(router.handle(.init(action: .markMealEaten, payload: ["id": meal.id.uuidString])))
        XCTAssertEqual(meal.status, .eaten)
        XCTAssertNotNil(meal.actualEatenAt)
    }

    func testMarkMealEatenReturnsFalseForUnknownIDOrAlreadyEaten() throws {
        let context = try makeContext()
        let router = makeRouter(configured: context)

        XCTAssertFalse(router.handle(.init(action: .markMealEaten, payload: ["id": UUID().uuidString])))

        let meal = PlannedMeal(dayDate: Date(), mealName: "Lunch", status: .eaten)
        context.insert(meal)
        try context.save()
        XCTAssertFalse(
            router.handle(.init(action: .markMealEaten, payload: ["id": meal.id.uuidString])),
            "Already eaten — never re-applies the meal-shift/macro-rebalance side effects"
        )
    }

    // MARK: - Workout

    func testStartWorkoutFlipsPlannedToInProgress() throws {
        let context = try makeContext()
        let router = makeRouter(configured: context)

        let plan = WorkoutPlan(date: Date(), type: .push)
        context.insert(plan)
        try context.save()

        XCTAssertTrue(router.handle(.init(action: .startWorkout, payload: [:])))
        XCTAssertEqual(plan.status, .inProgress)
        XCTAssertNotNil(plan.startedAt)
    }

    func testStartWorkoutNoOpsWithNoPlanOrAlreadyStarted() throws {
        let context = try makeContext()
        let router = makeRouter(configured: context)

        XCTAssertFalse(router.handle(.init(action: .startWorkout, payload: [:])), "No plan today")

        let plan = WorkoutPlan(date: Date(), type: .push)
        plan.status = .inProgress
        context.insert(plan)
        try context.save()
        XCTAssertFalse(
            router.handle(.init(action: .startWorkout, payload: [:])),
            "Already in progress — never touches ExerciseHistory/set completion"
        )
    }

    // MARK: - Focus Timer

    func testFocusTimerLifecycleStartPauseResumeStop() throws {
        let context = try makeContext()
        let router = makeRouter(configured: context)

        XCTAssertTrue(router.handle(.init(action: .startFocusTimer, payload: ["duration": "900"])))
        XCTAssertFalse(
            router.handle(.init(action: .startFocusTimer, payload: [:])),
            "A session is already active — starting a second one would leak the first"
        )
        XCTAssertTrue(router.handle(.init(action: .pauseFocusTimer, payload: [:])))
        XCTAssertTrue(router.handle(.init(action: .resumeFocusTimer, payload: [:])))
        XCTAssertTrue(router.handle(.init(action: .stopFocusTimer, payload: [:])))

        // Session cleared — a new one can start.
        XCTAssertTrue(router.handle(.init(action: .startFocusTimer, payload: [:])))
    }

    func testFocusTimerActionsNoOpWithNoActiveSession() throws {
        let context = try makeContext()
        let router = makeRouter(configured: context)

        XCTAssertFalse(router.handle(.init(action: .pauseFocusTimer, payload: [:])))
        XCTAssertFalse(router.handle(.init(action: .resumeFocusTimer, payload: [:])))
        XCTAssertFalse(router.handle(.init(action: .stopFocusTimer, payload: [:])))
    }

    // MARK: - Logged Set buffering

    func testLogSetBuffersUntilHandlerRegisteredThenReplays() throws {
        let context = try makeContext()
        let router = makeRouter(configured: context)

        let firstAction = WatchActionPayload(
            action: .logSet,
            payload: ["exercise": "Bench Press", "reps": "8", "weight": "80"]
        )

        // Arrives before Training has ever loaded — buffered, honestly not
        // yet applied.
        XCTAssertFalse(router.handle(firstAction))

        var replayed: [WatchActionPayload] = []
        router.setLogSetHandler { received in
            replayed.append(received)
            return true
        }

        XCTAssertEqual(replayed.count, 1, "The buffered set must replay on registration")
        XCTAssertEqual(replayed.first?.payload["exercise"], "Bench Press")

        // A genuinely NEW set (its own fresh id) routes straight through.
        let secondAction = WatchActionPayload(
            action: .logSet,
            payload: ["exercise": "Bench Press", "reps": "6", "weight": "82.5"]
        )
        XCTAssertTrue(router.handle(secondAction))
        XCTAssertEqual(replayed.count, 2)
    }

    // MARK: - Duplicate delivery (§11)

    func testDuplicateActionIDIsIgnoredButAcksSuccess() throws {
        let context = try makeContext()
        let router = makeRouter(configured: context)

        let nn = NonNegotiable(name: "Train", type: .train, targetValue: 1)
        context.insert(nn)
        try context.save()

        let action = WatchActionPayload(action: .markNonNegotiableDone, payload: ["id": nn.id.uuidString])
        XCTAssertTrue(router.handle(action), "First delivery applies for real")

        let progress = try XCTUnwrap(try context.fetch(FetchDescriptor<NonNegotiableProgress>()).first)
        XCTAssertTrue(progress.isCompleted)

        // A REDELIVERY of the exact same action (same id — e.g. WCSession
        // replaying a queued transferUserInfo) must not re-apply, but still
        // acks true — the watch already earned its success haptic.
        XCTAssertTrue(router.handle(action), "Duplicate delivery acks success without redoing the work")
    }

    func testLegacyPayloadWithoutIDStillDecodes() throws {
        let json = Data(#"{"action":"logSet","payload":{"exercise":"Bench","actionID":"abc"}}"#.utf8)
        let decoded = try JSONDecoder().decode(WatchActionPayload.self, from: json)
        XCTAssertEqual(decoded.action, .logSet)
        XCTAssertEqual(decoded.id, "abc", "falls back to the payload's actionID tag")
    }
}
