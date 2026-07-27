//
// CallInterruptionTests.swift
// Tempo
//
// STATE_MACHINES §1 — the interruptedCall state finally has real
// transitions. Pins: a live call parks an active session (capturing the
// exact sub-state), the call ending restores that state verbatim, and the
// handler no-ops from idle / paused / already-interrupted contexts so a
// stray CallKit event can never corrupt the session.
//

@testable import Tempo
import XCTest

@MainActor
final class CallInterruptionTests: XCTestCase {
    private func makeVM() -> TrainingViewModel {
        TrainingViewModel(
            trainingEngine: MockTrainingEngine(),
            whoop: MockWhoopService(),
            healthKit: MockHealthKitService()
        )
    }

    func testCallStartParksActiveSetState() {
        let vm = makeVM()
        vm.sessionState = .exercise(.setActive(exerciseIndex: 2, setIndex: 1))

        vm.handleCallChange(callEnded: false)

        XCTAssertEqual(
            vm.sessionState,
            .interruptedCall(previousState: .exercise(.setActive(exerciseIndex: 2, setIndex: 1))),
            "A live call captures the exact sub-state it interrupted"
        )
    }

    func testCallEndRestoresCapturedState() {
        let vm = makeVM()
        vm.sessionState = .exercise(.setActive(exerciseIndex: 2, setIndex: 1))
        vm.handleCallChange(callEnded: false)

        vm.handleCallChange(callEnded: true)

        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 2, setIndex: 1)),
                       "Hanging up restores the interrupted state verbatim")
    }

    func testCallWhileIdleIsIgnored() {
        let vm = makeVM()
        vm.sessionState = .idle

        vm.handleCallChange(callEnded: false)

        XCTAssertEqual(vm.sessionState, .idle, "No session → nothing to interrupt")
    }

    func testCallWhilePausedIsIgnored() {
        let vm = makeVM()
        let paused = WorkoutSessionState.paused(
            previousState: .exercise(.setActive(exerciseIndex: 0, setIndex: 0)),
            pauseStartTime: Date()
        )
        vm.sessionState = paused

        vm.handleCallChange(callEnded: false)

        XCTAssertEqual(vm.sessionState, paused,
                       "A manual pause outranks the call — don't stack interruptions")
    }

    func testCallEndWithoutInterruptionIsIgnored() {
        let vm = makeVM()
        vm.sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))

        vm.handleCallChange(callEnded: true)

        XCTAssertEqual(vm.sessionState, .exercise(.setActive(exerciseIndex: 0, setIndex: 0)),
                       "A call ending that we never parked for is a no-op")
    }

    func testWarmupInterruptionRestoresWarmup() {
        let vm = makeVM()
        vm.sessionState = .warmup(exerciseIndex: 0, warmupSetIndex: 1)

        vm.handleCallChange(callEnded: false)
        XCTAssertEqual(vm.sessionState,
                       .interruptedCall(previousState: .warmup(exerciseIndex: 0, warmupSetIndex: 1)))

        vm.handleCallChange(callEnded: true)
        XCTAssertEqual(vm.sessionState, .warmup(exerciseIndex: 0, warmupSetIndex: 1))
    }
}
