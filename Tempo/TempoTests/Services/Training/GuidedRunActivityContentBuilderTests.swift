//
// GuidedRunActivityContentBuilderTests.swift
// Tempo
//
// Guided run mode — mapping a live `GuidedRunSession` (driven by a
// FakeGuidedRunClock, same fixtures style as GuidedRunSessionTests) onto the
// `GuidedRunActivitySnapshot` the Live Activity/Watch both render.
//

@testable import Tempo
import XCTest

@MainActor
final class GuidedRunActivityContentBuilderTests: XCTestCase {
    private let blockA = UUID()

    // MARK: - Fixtures

    /// One block, two timed reps (cap 10s) with a 5s rest between.
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

    private func continuousPlan(targetSeconds: Double = 300) -> GuidedRunPlan {
        let block = GuidedRunBlock(
            id: blockA, name: "Fartleck", trainerText: "5 min run", rawDetail: nil,
            target: ConditioningTargetParser.parse(detail: nil), restSeconds: 60, restIsDefault: true
        )
        let steps = [
            GuidedRunStep(
                blockID: blockA, blockIndex: 0, blockCount: 1, blockName: "Fartleck", blockTrainerText: "5 min run",
                kind: .work(.continuousDuration(targetSeconds: targetSeconds))
            ),
        ]
        return GuidedRunPlan(blocks: [block], steps: steps)
    }

    // MARK: - Countdown

    func testCountdownSnapshot() throws {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        let tracker = GuidedRunLocationTracker()
        session.start()
        session.tick()
        XCTAssertEqual(session.phase, .countdown(secondsRemaining: 3))

        let now = clock.now()
        let snapshot = GuidedRunActivityContentBuilder.build(
            session: session, locationTracker: tracker, useMiles: false,
            heartRateBPM: nil, maxHeartRate: nil, now: now
        )
        let snapshot2 = try XCTUnwrap(snapshot)
        XCTAssertEqual(snapshot2.stepTitle, "GET READY")
        XCTAssertTrue(snapshot2.isCountdown)
        XCTAssertTrue(snapshot2.countsDown)
        XCTAssertEqual(snapshot2.timerAnchor, now.addingTimeInterval(3))
    }

    // MARK: - Work (timed rep)

    func testWorkSnapshotShowsCapAndOpenEndedCountUp() throws {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        let tracker = GuidedRunLocationTracker()
        session.start()
        clock.advance(3)
        session.tick() // -> work(0)
        clock.advance(4)
        session.tick()

        let now = clock.now()
        let snapshot = try XCTUnwrap(GuidedRunActivityContentBuilder.build(
            session: session, locationTracker: tracker, useMiles: false,
            heartRateBPM: 142, maxHeartRate: 190, now: now
        ))
        XCTAssertEqual(snapshot.stepTitle, "Shuttle · Rep 1/2")
        XCTAssertEqual(snapshot.detailText, "Cap 10\"")
        XCTAssertFalse(snapshot.isRest)
        XCTAssertFalse(snapshot.isPaused)
        XCTAssertFalse(snapshot.countsDown, "open-ended count up — no natural end to a rep")
        XCTAssertEqual(snapshot.timerAnchor, now.addingTimeInterval(-4), "anchored to the rep's own start, elapsed-adjusted")
        XCTAssertNil(snapshot.distanceText, "not a continuous step")
        XCTAssertEqual(snapshot.heartRateText, "142 bpm")
        XCTAssertEqual(snapshot.heartRateZone, 3, "142/190 = 74.7% -> Z3")
    }

    func testPausedWorkSnapshotFreezesInsteadOfTicking() throws {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        let tracker = GuidedRunLocationTracker()
        session.start()
        clock.advance(3)
        session.tick() // -> work(0)
        clock.advance(4)
        session.tick() // elapsedInCurrentStep now reflects the +4
        session.pause()

        let snapshot = try XCTUnwrap(GuidedRunActivityContentBuilder.build(
            session: session, locationTracker: tracker, useMiles: false,
            heartRateBPM: nil, maxHeartRate: nil, now: clock.now()
        ))
        XCTAssertTrue(snapshot.isPaused)
        XCTAssertEqual(snapshot.frozenText, "0:04")
    }

    // MARK: - Rest

    func testRestSnapshotCountsDownAndNamesTheNextRep() throws {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        let tracker = GuidedRunLocationTracker()
        session.start()
        clock.advance(3)
        session.tick() // work(0)
        session.markDone() // -> rest(1), 5s rest
        session.tick() // computes remainingInCurrentStep for the fresh rest phase

        let now = clock.now()
        let snapshot = try XCTUnwrap(GuidedRunActivityContentBuilder.build(
            session: session, locationTracker: tracker, useMiles: false,
            heartRateBPM: nil, maxHeartRate: nil, now: now
        ))
        XCTAssertEqual(snapshot.stepTitle, "REST")
        XCTAssertTrue(snapshot.isRest)
        XCTAssertTrue(snapshot.countsDown)
        XCTAssertEqual(snapshot.timerAnchor, now.addingTimeInterval(5))
        XCTAssertEqual(snapshot.nextStepText, "Next: Rep 2/2")
    }

    func testRestSnapshotWithNoNextRepPointsToFinish() throws {
        // One rep followed by a trailing rest with nothing queued after it —
        // exercises the "Next: Finish" fallback in a rest that ISN'T
        // followed by another work step.
        let block = GuidedRunBlock(
            id: blockA, name: "Shuttle", trainerText: "1 rep", rawDetail: "1 rep of 10y < 10\"",
            target: ConditioningTargetParser.parse(detail: "1 rep of 10y < 10\""), restSeconds: 5, restIsDefault: false
        )
        let steps = [
            GuidedRunStep(
                blockID: blockA, blockIndex: 0, blockCount: 1, blockName: "Shuttle", blockTrainerText: "1 rep",
                kind: .work(.timedRep(GuidedRunTimedRep(index: 0, of: 1, capSeconds: 10, distanceMeters: nil, distanceLabel: nil)))
            ),
            GuidedRunStep(
                blockID: blockA, blockIndex: 0, blockCount: 1, blockName: "Shuttle", blockTrainerText: "1 rep",
                kind: .rest(seconds: 5)
            ),
        ]
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: GuidedRunPlan(blocks: [block], steps: steps), clock: clock)
        let tracker = GuidedRunLocationTracker()
        session.start()
        clock.advance(3)
        session.tick() // work(0)
        session.markDone() // -> rest(1), nothing queued after it
        session.tick()

        let snapshot = try XCTUnwrap(GuidedRunActivityContentBuilder.build(
            session: session, locationTracker: tracker, useMiles: false,
            heartRateBPM: nil, maxHeartRate: nil, now: clock.now()
        ))
        XCTAssertEqual(snapshot.nextStepText, "Next: Finish")
    }

    // MARK: - Continuous work

    func testContinuousWorkShowsDistanceAndPaceFields() throws {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: continuousPlan(), clock: clock)
        let tracker = GuidedRunLocationTracker()
        session.start()
        clock.advance(3)
        session.tick() // -> work(0), continuous duration

        let snapshot = try XCTUnwrap(GuidedRunActivityContentBuilder.build(
            session: session, locationTracker: tracker, useMiles: false,
            heartRateBPM: nil, maxHeartRate: nil, now: clock.now()
        ))
        XCTAssertEqual(snapshot.stepTitle, "Fartleck · In progress")
        XCTAssertEqual(snapshot.detailText, "5 min target")
        XCTAssertNotNil(snapshot.distanceText, "continuous steps always report a distance field, even at 0")
    }

    // MARK: - Idle / finished

    func testIdleAndFinishedProduceNoSnapshot() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        let tracker = GuidedRunLocationTracker()
        XCTAssertNil(GuidedRunActivityContentBuilder.build(
            session: session, locationTracker: tracker, useMiles: false,
            heartRateBPM: nil, maxHeartRate: nil, now: clock.now()
        ))
    }
}
