//
// GuidedRunLiveCoordinatorTests.swift
// Tempo
//
// Apple Watch run mode — every wrist tap the coordinator can receive
// (`handleWatchAction`) reaches the real, live `GuidedRunSession` exactly
// like the on-screen button would, and a session-less coordinator fails
// closed rather than silently succeeding.
//

@testable import Tempo
import XCTest

@MainActor
final class GuidedRunLiveCoordinatorTests: XCTestCase {
    private let blockA = UUID()
    /// `GuidedRunLiveCoordinator.locationTracker` is `weak` (the real owner
    /// is `GuidedRunView`'s own `@State`) — tests need their own strong
    /// holder so the tracker isn't deallocated the instant it's assigned.
    private var retainedTrackers: [GuidedRunLocationTracker] = []

    /// One timed rep (cap 10s) then a 5s rest then a second rep — enough to
    /// exercise mark-done/skip/pause/resume without finishing the plan.
    private func repsPlan() -> GuidedRunPlan {
        let block = GuidedRunBlock(
            id: blockA, name: "Shuttle", trainerText: "2 reps", rawDetail: "2 reps of 10y < 10\"",
            target: ConditioningTargetParser.parse(detail: "2 reps of 10y < 10\""), restSeconds: 5, restIsDefault: false
        )
        let steps = [
            GuidedRunStep(
                blockID: blockA, blockIndex: 0, blockCount: 1, blockName: "Shuttle", blockTrainerText: "2 reps",
                kind: .work(.timedRep(GuidedRunTimedRep(index: 0, of: 2, capSeconds: 10, distanceMeters: nil, distanceLabel: nil)))
            ),
            GuidedRunStep(
                blockID: blockA, blockIndex: 0, blockCount: 1, blockName: "Shuttle", blockTrainerText: "2 reps",
                kind: .rest(seconds: 5)
            ),
            GuidedRunStep(
                blockID: blockA, blockIndex: 0, blockCount: 1, blockName: "Shuttle", blockTrainerText: "2 reps",
                kind: .work(.timedRep(GuidedRunTimedRep(index: 1, of: 2, capSeconds: 10, distanceMeters: nil, distanceLabel: nil)))
            ),
        ]
        return GuidedRunPlan(blocks: [block], steps: steps)
    }

    private func makeLiveSession() -> (session: GuidedRunSession, clock: FakeGuidedRunClock, coordinator: GuidedRunLiveCoordinator) {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        session.start()
        clock.advance(3)
        session.tick() // -> work(0)

        let tracker = GuidedRunLocationTracker()
        retainedTrackers.append(tracker)
        let coordinator = GuidedRunLiveCoordinator()
        coordinator.start(session: session, runTitle: "Conditioning", useMiles: false, maxHeartRate: 190)
        coordinator.locationTracker = tracker
        return (session, clock, coordinator)
    }

    // MARK: - No session registered

    func testActionsFailClosedWithNoSession() {
        let coordinator = GuidedRunLiveCoordinator()
        XCTAssertFalse(coordinator.handleWatchAction(.init(action: .guidedRunMarkDone, payload: [:])))
        XCTAssertFalse(coordinator.handleWatchAction(.init(action: .guidedRunHeartRate, payload: ["bpm": "140"])))
    }

    // MARK: - Mark done

    func testGuidedRunMarkDoneCompletesTheCurrentRepOnTheRealSession() {
        let (session, _, coordinator) = makeLiveSession()
        XCTAssertEqual(session.phase, .work(stepIndex: 0))

        XCTAssertTrue(coordinator.handleWatchAction(.init(action: .guidedRunMarkDone, payload: [:])))

        XCTAssertEqual(session.phase, .rest(stepIndex: 1))
        XCTAssertEqual(session.results[blockA]?.repTimesSeconds.count, 1)
    }

    // MARK: - Skip rep

    func testGuidedRunSkipRepAdvancesWithoutRecordingATime() {
        let (session, _, coordinator) = makeLiveSession()

        XCTAssertTrue(coordinator.handleWatchAction(.init(action: .guidedRunSkipRep, payload: [:])))

        XCTAssertEqual(session.phase, .rest(stepIndex: 1))
        XCTAssertEqual(session.results[blockA]?.repTimesSeconds, [], "skipped, not timed")
        XCTAssertEqual(session.results[blockA]?.skippedCount, 1)
    }

    // MARK: - Pause / resume

    func testGuidedRunPauseAndResumeMirrorTheButtons() {
        let (session, _, coordinator) = makeLiveSession()
        XCTAssertFalse(session.isPaused)

        XCTAssertTrue(coordinator.handleWatchAction(.init(action: .guidedRunPause, payload: [:])))
        XCTAssertTrue(session.isPaused)

        XCTAssertTrue(coordinator.handleWatchAction(.init(action: .guidedRunResume, payload: [:])))
        XCTAssertFalse(session.isPaused)
    }

    // MARK: - Heart rate relay

    func testGuidedRunHeartRateUpdatesTheLiveSession() {
        let (session, _, coordinator) = makeLiveSession()

        XCTAssertTrue(coordinator.handleWatchAction(.init(action: .guidedRunHeartRate, payload: ["bpm": "148"])))

        XCTAssertEqual(session.currentHeartRateBPM, 148)
        XCTAssertEqual(session.results[blockA]?.heartRateSamplesBPM, [148])
    }

    func testGuidedRunHeartRateFailsClosedWithoutAParsableBPM() {
        let (_, _, coordinator) = makeLiveSession()
        XCTAssertFalse(coordinator.handleWatchAction(.init(action: .guidedRunHeartRate, payload: ["bpm": "not-a-number"])))
        XCTAssertFalse(coordinator.handleWatchAction(.init(action: .guidedRunHeartRate, payload: [:])))
    }

    // MARK: - Unrelated actions

    func testUnrelatedActionsAreIgnored() {
        let (_, _, coordinator) = makeLiveSession()
        XCTAssertFalse(coordinator.handleWatchAction(.init(action: .logSet, payload: [:])))
    }

    // MARK: - End clears session tracking

    func testEndStopsFurtherHandling() {
        let (session, _, coordinator) = makeLiveSession()
        coordinator.end()
        // The session reference itself is untouched by `end()` — only the
        // Activity/Watch fan-out stops — so a stray action still reaches the
        // real session exactly as `handleWatchAction` always would; `end()`
        // is what GuidedRunView calls, which also clears the router
        // registration so nothing reaches here again in production.
        XCTAssertTrue(coordinator.handleWatchAction(.init(action: .guidedRunPause, payload: [:])))
        XCTAssertTrue(session.isPaused)
    }
}
