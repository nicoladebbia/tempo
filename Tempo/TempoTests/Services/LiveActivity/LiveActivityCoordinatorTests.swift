//
// LiveActivityCoordinatorTests.swift
// Tempo
//
// The coordinator's whole job is priority arbitration + serialization
// between three independent Live Activity kinds — exercised here entirely
// through fake, protocol-injected participants. No ActivityKit involved:
// `LiveActivityCoordinator` never imports the framework, which is exactly
// what makes this possible.
//

@testable import Tempo
import XCTest

// MARK: - FakeLiveActivityParticipant

@MainActor
private final class FakeLiveActivityParticipant: LiveActivityParticipant {
    var hasActiveLiveSession = true
    private(set) var suspendCount = 0
    private(set) var resumeCount = 0

    func suspendLiveActivity() async {
        suspendCount += 1
    }

    func resumeLiveActivityIfNeeded() async {
        resumeCount += 1
    }
}

// MARK: - LiveActivityCoordinatorTests

@MainActor
final class LiveActivityCoordinatorTests: XCTestCase {
    private var coordinator: LiveActivityCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        coordinator = LiveActivityCoordinator.shared
        // Earlier test classes drive the shared coordinator through real view
        // models (slow ActivityKit calls). Let that chain finish, or it keeps
        // mutating activeKind mid-test after the reset.
        await coordinator.waitUntilIdle()
        coordinator.resetForTesting()
    }

    override func tearDown() async throws {
        await coordinator.waitUntilIdle()
        coordinator.resetForTesting()
        try await super.tearDown()
    }

    // MARK: - Priority: a higher-priority start suspends the lower one

    func testHigherPriorityStartSuspendsLowerAndBecomesActive() async {
        let workout = FakeLiveActivityParticipant()
        coordinator.register(workout, for: .gymWorkout)
        var workoutStarted = false
        coordinator.start(.gymWorkout) { workoutStarted = true }
        await coordinator.waitUntilIdle()
        XCTAssertTrue(workoutStarted)
        XCTAssertEqual(coordinator.activeKind, .gymWorkout)

        let run = FakeLiveActivityParticipant()
        coordinator.register(run, for: .guidedRun)
        var runStarted = false
        coordinator.start(.guidedRun) { runStarted = true }
        await coordinator.waitUntilIdle()

        XCTAssertTrue(runStarted)
        XCTAssertEqual(workout.suspendCount, 1)
        XCTAssertEqual(coordinator.activeKind, .guidedRun)
        XCTAssertTrue(coordinator.suspendedKinds.contains(.gymWorkout))
    }

    // MARK: - Priority: a lower-priority start while a higher one is active never shows

    func testLowerPriorityStartWhileHigherActiveDoesNotRunStartWork() async {
        let run = FakeLiveActivityParticipant()
        coordinator.register(run, for: .guidedRun)
        coordinator.start(.guidedRun) {}
        await coordinator.waitUntilIdle()

        let focus = FakeLiveActivityParticipant()
        coordinator.register(focus, for: .focusTimer)
        var focusStarted = false
        coordinator.start(.focusTimer) { focusStarted = true }
        await coordinator.waitUntilIdle()

        XCTAssertFalse(focusStarted, "a lower-priority kind must never show while a higher one owns the screen")
        XCTAssertTrue(coordinator.suspendedKinds.contains(.focusTimer))
        XCTAssertEqual(coordinator.activeKind, .guidedRun)
    }

    // MARK: - Resume: ending the active kind resumes the highest-priority alive suspended one

    func testEndingActiveResumesHighestPrioritySuspendedAliveParticipant() async {
        let workout = FakeLiveActivityParticipant()
        coordinator.register(workout, for: .gymWorkout)
        coordinator.start(.gymWorkout) {}
        await coordinator.waitUntilIdle()

        let run = FakeLiveActivityParticipant()
        coordinator.register(run, for: .guidedRun)
        coordinator.start(.guidedRun) {}
        await coordinator.waitUntilIdle()
        XCTAssertEqual(workout.suspendCount, 1)

        coordinator.end(.guidedRun) {}
        await coordinator.waitUntilIdle()

        XCTAssertEqual(workout.resumeCount, 1)
        XCTAssertEqual(coordinator.activeKind, .gymWorkout)
        XCTAssertFalse(coordinator.suspendedKinds.contains(.gymWorkout))
    }

    // MARK: - Resume skips a suspended participant whose session already ended

    func testEndingActiveSkipsSuspendedParticipantWhoseSessionEnded() async {
        let workout = FakeLiveActivityParticipant()
        coordinator.register(workout, for: .gymWorkout)
        coordinator.start(.gymWorkout) {}
        await coordinator.waitUntilIdle()

        let run = FakeLiveActivityParticipant()
        coordinator.register(run, for: .guidedRun)
        coordinator.start(.guidedRun) {}
        await coordinator.waitUntilIdle()

        // The workout was discarded for real WHILE it was suspended.
        workout.hasActiveLiveSession = false

        coordinator.end(.guidedRun) {}
        await coordinator.waitUntilIdle()

        XCTAssertEqual(workout.resumeCount, 0)
        XCTAssertNil(coordinator.activeKind)
    }

    // MARK: - Full priority chain: guided run > gym workout > focus timer

    func testPriorityChainResumesGymWorkoutBeforeFocusTimer() async {
        let focus = FakeLiveActivityParticipant()
        coordinator.register(focus, for: .focusTimer)
        coordinator.start(.focusTimer) {}
        await coordinator.waitUntilIdle()

        let workout = FakeLiveActivityParticipant()
        coordinator.register(workout, for: .gymWorkout)
        coordinator.start(.gymWorkout) {}
        await coordinator.waitUntilIdle()
        XCTAssertEqual(focus.suspendCount, 1, "starting the workout must suspend the lower-priority focus timer")

        let run = FakeLiveActivityParticipant()
        coordinator.register(run, for: .guidedRun)
        coordinator.start(.guidedRun) {}
        await coordinator.waitUntilIdle()
        XCTAssertEqual(workout.suspendCount, 1, "starting the run must suspend the lower-priority workout")

        // Ending the run resumes the workout (higher-priority suspended kind), not the focus timer.
        coordinator.end(.guidedRun) {}
        await coordinator.waitUntilIdle()
        XCTAssertEqual(workout.resumeCount, 1)
        XCTAssertEqual(focus.resumeCount, 0)
        XCTAssertEqual(coordinator.activeKind, .gymWorkout)

        // Ending the workout for real finally resumes the focus timer.
        coordinator.end(.gymWorkout) {}
        await coordinator.waitUntilIdle()
        XCTAssertEqual(focus.resumeCount, 1)
        XCTAssertEqual(coordinator.activeKind, .focusTimer)
    }

    // MARK: - Serialization: calls apply in issued order, not completion order

    func testCallsApplyInIssuedOrderNotCompletionOrder() async {
        var order: [String] = []
        coordinator.start(.gymWorkout) {
            // A slow first call must not let a later one overtake it.
            try? await Task.sleep(for: .milliseconds(50))
            order.append("first")
        }
        coordinator.update {
            order.append("second")
        }
        coordinator.update {
            order.append("third")
        }
        await coordinator.waitUntilIdle()
        XCTAssertEqual(order, ["first", "second", "third"])
    }

    // MARK: - Ending a merely-suspended (never active) kind disturbs nothing

    func testEndingASuspendedNotActiveKindDoesNotResumeAnythingOrDisturbTheActiveKind() async {
        let run = FakeLiveActivityParticipant()
        coordinator.register(run, for: .guidedRun)
        coordinator.start(.guidedRun) {}
        await coordinator.waitUntilIdle()

        let focus = FakeLiveActivityParticipant()
        coordinator.register(focus, for: .focusTimer)
        coordinator.start(.focusTimer) {} // suspended immediately — the run outranks it
        await coordinator.waitUntilIdle()
        XCTAssertTrue(coordinator.suspendedKinds.contains(.focusTimer))

        // The focus session itself is cancelled while still suspended.
        coordinator.end(.focusTimer) {}
        await coordinator.waitUntilIdle()

        XCTAssertEqual(focus.resumeCount, 0)
        XCTAssertFalse(coordinator.suspendedKinds.contains(.focusTimer))
        XCTAssertEqual(coordinator.activeKind, .guidedRun, "ending a kind that was never on screen must not touch the real active one")
    }

    // MARK: - Restarting the same kind is a no-op for priority bookkeeping

    func testRestartingTheSameActiveKindDoesNotSuspendItself() async {
        let workout = FakeLiveActivityParticipant()
        coordinator.register(workout, for: .gymWorkout)
        coordinator.start(.gymWorkout) {}
        await coordinator.waitUntilIdle()

        var secondStartRan = false
        coordinator.start(.gymWorkout) { secondStartRan = true }
        await coordinator.waitUntilIdle()

        XCTAssertTrue(secondStartRan)
        XCTAssertEqual(workout.suspendCount, 0)
        XCTAssertEqual(coordinator.activeKind, .gymWorkout)
    }
}
