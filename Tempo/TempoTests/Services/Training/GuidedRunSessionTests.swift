//
// GuidedRunSessionTests.swift
// Tempo
//
// Guided run mode — the state machine, entirely off a `FakeGuidedRunClock`
// so every timer (countdown, rep, rest, halfway/ten-seconds cues) is
// asserted deterministically with zero real waiting.
//

@testable import Tempo
import XCTest

@MainActor
final class GuidedRunSessionTests: XCTestCase {
    private let blockA = UUID()
    private let blockB = UUID()

    // MARK: - Fixtures

    /// blockA: 2 timed reps (cap 10s) with a 5s rest between.
    private func repsPlan() -> GuidedRunPlan {
        let block = GuidedRunBlock(
            id: blockA, name: "Shuttle", trainerText: "2 reps", rawDetail: "2 reps of 10y < 10\"",
            target: ConditioningTargetParser.parse(detail: "2 reps of 10y < 10\""), restSeconds: 5, restIsDefault: false
        )
        let steps = [
            GuidedRunStep(
                blockID: blockA,
                blockIndex: 0,
                blockCount: 1,
                blockName: "Shuttle",
                blockTrainerText: "2 reps",
                kind: .work(.timedRep(GuidedRunTimedRep(index: 0, of: 2, capSeconds: 10, distanceMeters: 9.14, distanceLabel: "10y")))
            ),
            GuidedRunStep(
                blockID: blockA,
                blockIndex: 0,
                blockCount: 1,
                blockName: "Shuttle",
                blockTrainerText: "2 reps",
                kind: .rest(seconds: 5)
            ),
            GuidedRunStep(
                blockID: blockA,
                blockIndex: 0,
                blockCount: 1,
                blockName: "Shuttle",
                blockTrainerText: "2 reps",
                kind: .work(.timedRep(GuidedRunTimedRep(index: 1, of: 2, capSeconds: 10, distanceMeters: 9.14, distanceLabel: "10y")))
            ),
        ]
        return GuidedRunPlan(blocks: [block], steps: steps)
    }

    /// blockA: one 20s continuous duration step.
    private func durationPlan(targetSeconds: Double = 20) -> GuidedRunPlan {
        let block = GuidedRunBlock(
            id: blockA, name: "Fartleck", trainerText: "20s run", rawDetail: nil,
            target: ConditioningTargetParser.parse(detail: nil), restSeconds: 60, restIsDefault: true
        )
        let steps = [
            GuidedRunStep(
                blockID: blockA,
                blockIndex: 0,
                blockCount: 1,
                blockName: "Fartleck",
                blockTrainerText: "20s run",
                kind: .work(.continuousDuration(targetSeconds: targetSeconds))
            ),
        ]
        return GuidedRunPlan(blocks: [block], steps: steps)
    }

    /// blockA (2 reps) then blockB (1 round) — for skipBlock/multi-block tests.
    private func twoBlockPlan() -> GuidedRunPlan {
        let blockAModel = GuidedRunBlock(
            id: blockA, name: "Shuttle", trainerText: "2 reps", rawDetail: "2 reps of 10y < 10\"",
            target: ConditioningTargetParser.parse(detail: "2 reps of 10y < 10\""), restSeconds: 5, restIsDefault: false
        )
        let blockBModel = GuidedRunBlock(
            id: blockB, name: "Drill", trainerText: "1 round", rawDetail: "2 x 1times",
            target: ConditioningTargetParser.parse(detail: "2 x 1times"), restSeconds: 5, restIsDefault: true
        )
        let steps = [
            GuidedRunStep(
                blockID: blockA,
                blockIndex: 0,
                blockCount: 2,
                blockName: "Shuttle",
                blockTrainerText: "2 reps",
                kind: .work(.timedRep(GuidedRunTimedRep(index: 0, of: 2, capSeconds: 10, distanceMeters: nil, distanceLabel: nil)))
            ),
            GuidedRunStep(
                blockID: blockA,
                blockIndex: 0,
                blockCount: 2,
                blockName: "Shuttle",
                blockTrainerText: "2 reps",
                kind: .rest(seconds: 5)
            ),
            GuidedRunStep(
                blockID: blockA,
                blockIndex: 0,
                blockCount: 2,
                blockName: "Shuttle",
                blockTrainerText: "2 reps",
                kind: .work(.timedRep(GuidedRunTimedRep(index: 1, of: 2, capSeconds: 10, distanceMeters: nil, distanceLabel: nil)))
            ),
            GuidedRunStep(
                blockID: blockB,
                blockIndex: 1,
                blockCount: 2,
                blockName: "Drill",
                blockTrainerText: "1 round",
                kind: .work(.round(index: 0, of: 2))
            ),
            GuidedRunStep(
                blockID: blockB,
                blockIndex: 1,
                blockCount: 2,
                blockName: "Drill",
                blockTrainerText: "1 round",
                kind: .rest(seconds: 5)
            ),
            GuidedRunStep(
                blockID: blockB,
                blockIndex: 1,
                blockCount: 2,
                blockName: "Drill",
                blockTrainerText: "1 round",
                kind: .work(.round(index: 1, of: 2))
            ),
        ]
        return GuidedRunPlan(blocks: [blockAModel, blockBModel], steps: steps)
    }

    // MARK: - Countdown

    func testCountdownFiresThreeTwoOneThenGoAndEntersFirstWorkStep() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        var cues: [GuidedRunCue] = []
        session.cueHandler = { cues.append($0) }

        session.start()
        session.tick()
        XCTAssertEqual(session.phase, .countdown(secondsRemaining: 3))
        XCTAssertEqual(cues, [.countdown(3)])

        clock.advance(1)
        session.tick()
        XCTAssertEqual(session.phase, .countdown(secondsRemaining: 2))

        clock.advance(1)
        session.tick()
        XCTAssertEqual(session.phase, .countdown(secondsRemaining: 1))

        clock.advance(1)
        session.tick()
        XCTAssertEqual(session.phase, .work(stepIndex: 0))
        XCTAssertEqual(cues, [.countdown(3), .countdown(2), .countdown(1), .go])
    }

    // MARK: - Timed reps + rest

    func testMarkDoneRecordsRepTimeAndEntersRest() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        session.start()
        clock.advance(3)
        session.tick() // enters work(0)
        XCTAssertEqual(session.phase, .work(stepIndex: 0))

        clock.advance(7) // 7s rep time, under the 10s cap
        session.markDone()

        XCTAssertEqual(session.phase, .rest(stepIndex: 1))
        let record = session.results[blockA]
        XCTAssertEqual(record?.repTimesSeconds, [7])
        XCTAssertEqual(record?.repChecks(capSeconds: 10), [true])
    }

    func testRestAutoAdvancesAfterItsDurationAndFiresTenSecondsCue() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        var cues: [GuidedRunCue] = []
        session.cueHandler = { cues.append($0) }

        session.start()
        clock.advance(3)
        session.tick() // work(0)
        session.markDone() // -> rest(1), 5s rest
        XCTAssertEqual(session.phase, .rest(stepIndex: 1))
        XCTAssertTrue(cues.contains(.restStart))

        clock.advance(2) // 3s remaining -> under the 10s threshold, cue fires
        session.tick()
        XCTAssertTrue(cues.contains(.tenSecondsLeft))
        XCTAssertEqual(session.phase, .rest(stepIndex: 1), "not done yet")

        clock.advance(3) // rest's 5s fully elapsed
        session.tick()
        XCTAssertEqual(session.phase, .work(stepIndex: 2))
    }

    func testSecondRepOverCapRecordsFalseCheck() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        session.start()
        clock.advance(3)
        session.tick()
        session.markDone() // rep 1, 0s (fast) -> rest
        clock.advance(5)
        session.tick() // rest elapses -> work(2)
        XCTAssertEqual(session.phase, .work(stepIndex: 2))

        clock.advance(12) // over the 10s cap
        session.markDone()

        let record = session.results[blockA]
        XCTAssertEqual(record?.repTimesSeconds, [0, 12])
        XCTAssertEqual(record?.repChecks(capSeconds: 10), [true, false])
        XCTAssertEqual(session.phase, .finished)
    }

    // MARK: - Pause / resume

    func testPauseFreezesElapsedAndResumeContinues() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        session.start()
        clock.advance(3)
        session.tick() // work(0)

        clock.advance(3)
        session.tick()
        XCTAssertEqual(session.elapsedInCurrentStep, 3)

        session.pause()
        XCTAssertTrue(session.isPaused)
        clock.advance(100) // large gap while paused must not count
        session.tick()
        XCTAssertEqual(session.elapsedInCurrentStep, 3)

        session.resume()
        clock.advance(2)
        session.tick()
        XCTAssertEqual(session.elapsedInCurrentStep, 5)

        session.markDone()
        XCTAssertEqual(session.results[blockA]?.repTimesSeconds, [5])
    }

    func testMarkDoneIgnoredWhilePaused() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        session.start()
        clock.advance(3)
        session.tick()
        session.pause()
        session.markDone()
        XCTAssertEqual(session.phase, .work(stepIndex: 0), "paused — markDone must no-op")
        XCTAssertNil(session.results[blockA])
    }

    func testSkipRepSkipBlockAndAddRepAllIgnoredWhilePaused() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        session.start()
        clock.advance(3)
        session.tick()
        let stepsBeforePause = session.steps.count

        session.pause()
        session.skipRep()
        session.skipBlock()
        session.addRep()

        XCTAssertEqual(session.phase, .work(stepIndex: 0), "paused — skip/add actions must all no-op")
        XCTAssertNil(session.results[blockA])
        XCTAssertEqual(session.steps.count, stepsBeforePause, "addRep must not mutate steps while paused")
    }

    // MARK: - Skip rep / skip block / add rep

    func testSkipRepRecordsNoTimeButCountsSkipped() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        session.start()
        clock.advance(3)
        session.tick()

        session.skipRep()

        XCTAssertEqual(session.phase, .rest(stepIndex: 1))
        XCTAssertEqual(session.results[blockA]?.repTimesSeconds, [])
        XCTAssertEqual(session.results[blockA]?.skippedCount, 1)
    }

    func testSkipBlockJumpsToNextBlockAndCountsAllRemainingWorkStepsSkipped() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: twoBlockPlan(), clock: clock)
        session.start()
        clock.advance(3)
        session.tick() // work(0), block A

        session.skipBlock()

        XCTAssertEqual(session.phase, .work(stepIndex: 3), "first step of block B")
        XCTAssertEqual(session.results[blockA]?.skippedCount, 2, "both of block A's reps")
    }

    func testAddRepInsertsAnotherRepAtEndOfCurrentBlock() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        session.start()
        clock.advance(3)
        session.tick() // work(0)

        XCTAssertEqual(session.steps.count, 3)
        session.addRep()
        XCTAssertEqual(session.steps.count, 5, "one rest + one work inserted")
        XCTAssertTrue(session.steps[3].kind == .rest(seconds: 5))
        guard case .work(.timedRep) = session.steps[4].kind else {
            return XCTFail("expected the appended step to be another timed rep")
        }

        // Finishing all three original steps must now land on the new rep,
        // not `.finished`.
        session.markDone() // rep 0 -> rest(1)
        clock.advance(5)
        session.tick() // -> work(2)
        session.markDone() // rep 1 -> now the NEW rest(3)
        XCTAssertEqual(session.phase, .rest(stepIndex: 3))
        clock.advance(5)
        session.tick()
        XCTAssertEqual(session.phase, .work(stepIndex: 4))
        session.markDone()
        XCTAssertEqual(session.phase, .finished)
        XCTAssertEqual(session.results[blockA]?.repTimesSeconds.count, 3)
    }

    // MARK: - Continuous duration + halfway cue

    func testContinuousDurationFiresHalfwayOnceAndTracksRemaining() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: durationPlan(targetSeconds: 20), clock: clock)
        var cues: [GuidedRunCue] = []
        session.cueHandler = { cues.append($0) }
        session.start()
        clock.advance(3)
        session.tick() // work(0)

        clock.advance(9)
        session.tick()
        XCTAssertFalse(cues.contains(.halfway))
        XCTAssertEqual(session.remainingInCurrentStep, 11)

        clock.advance(2) // 11s elapsed, past halfway (10s)
        session.tick()
        XCTAssertEqual(cues.filter { $0 == .halfway }.count, 1)

        clock.advance(5)
        session.tick()
        XCTAssertEqual(cues.filter { $0 == .halfway }.count, 1, "fires only once")

        session.markDone()
        XCTAssertEqual(session.phase, .finished)
        XCTAssertEqual(session.results[blockA]?.durationSeconds, 16)
        XCTAssertTrue(cues.contains(.done))
    }

    // MARK: - End early

    func testEndEarlyKeepsWhateverWasRecorded() {
        let clock = FakeGuidedRunClock()
        let session = GuidedRunSession(plan: repsPlan(), clock: clock)
        session.start()
        clock.advance(3)
        session.tick()
        clock.advance(4)
        session.markDone()

        session.endEarly()

        XCTAssertEqual(session.phase, .endedEarly)
        XCTAssertEqual(session.results[blockA]?.repTimesSeconds, [4])
        session.markDone() // no-op once ended
        XCTAssertEqual(session.phase, .endedEarly)
    }

    // MARK: - Empty plan

    func testStartingAnEmptyPlanGoesStraightToFinished() {
        let session = GuidedRunSession(plan: GuidedRunPlan(blocks: [], steps: []), clock: FakeGuidedRunClock())
        session.start()
        XCTAssertEqual(session.phase, .finished)
    }
}
