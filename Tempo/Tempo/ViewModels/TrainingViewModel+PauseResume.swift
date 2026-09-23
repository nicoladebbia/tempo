//
// TrainingViewModel+PauseResume.swift
// Tempo
//
// Pause/resume and phone-call interruption handling, split out of
// TrainingViewModel.swift to keep that file under the SwiftLint length caps.
// Pure VM behavior — same instance members, hosted in an extension.
//
// §2 fix — a pause or call interruption that catches the session mid-REST
// used to come back with the rest timer dead: `stopRestTimer()` wipes
// `restEndDate`/`restTimerTask`, and `restore()` never restarted them, so
// RestTimerView showed 0:00 forever. `captureRestRemainingBeforeStop()` +
// `pausedRestRemaining` (declared in the main file — extensions can't add
// stored properties) close that gap.
//

import CallKit
import Foundation

extension TrainingViewModel {
    // MARK: - Pause / Resume

    // Per STATE_MACHINES.md — any active → paused

    /// Snapshot of the current live state for the pause/interruption overlays.
    /// nil when the session isn't in a pausable state.
    private func capturePausedFromState() -> WorkoutSessionState.PausedFromState? {
        switch sessionState {
        case let .warmup(ei, si):
            .warmup(exerciseIndex: ei, warmupSetIndex: si)
        case let .exercise(sub):
            .exercise(sub)
        case .cooldown:
            .cooldown
        default:
            nil
        }
    }

    /// Snapshot the live rest countdown BEFORE `stopRestTimer()` wipes
    /// `restEndDate` — `sessionState`'s own `.resting(remainingSeconds:)` is
    /// stamped once at rest-start and never updated per tick, so it cannot
    /// be used to resume the timer accurately.
    private func captureRestRemainingBeforeStop() -> TimeInterval? {
        guard case .exercise(.resting) = sessionState, let end = restEndDate else {
            return nil
        }
        return max(0, end.timeIntervalSinceNow)
    }

    /// Re-enter the state a pause/interruption captured, re-arming the right
    /// clock (warm-up move timer during warm-up; the elapsed clock otherwise;
    /// the rest timer too, if the interruption caught a rest mid-countdown).
    private func restore(_ previousState: WorkoutSessionState.PausedFromState) {
        switch previousState {
        case let .warmup(ei, si):
            sessionState = .warmup(exerciseIndex: ei, warmupSetIndex: si)
            // Re-arm the guided warm-up move timer; the elapsed clock does not
            // run during warm-up, so don't start it here.
            startWarmupMoveTimerForCurrent()
            return
        case let .exercise(sub):
            sessionState = .exercise(sub)
            // §2 fix — a pause/call during REST used to come back with the
            // timer dead (stopped, never restarted): RestTimerView showed
            // 0:00 forever and the session was effectively stuck. Restart it
            // at the captured remaining time, toward the same next action.
            if case .resting = sub, let remaining = pausedRestRemaining {
                startRestTimer(duration: remaining, nextAction: pendingRestAction)
            }
        case .cooldown:
            sessionState = .cooldown
        }

        pausedRestRemaining = nil
        startElapsedTimer()
    }

    func pause() {
        guard sessionState.isActive, let previousState = capturePausedFromState() else {
            return
        }

        pausedRestRemaining = captureRestRemainingBeforeStop()
        stopRestTimer()
        stopWarmupMoveTimer()
        stopElapsedTimer()
        sessionState = .paused(previousState: previousState, pauseStartTime: Date())
    }

    func resume() {
        guard case let .paused(previousState, pauseStart) = sessionState else {
            return
        }

        // Track pause duration
        totalPauseDuration += Date().timeIntervalSince(pauseStart)

        restore(previousState)
    }

    // MARK: - Call Interruption (STATE_MACHINES §1 — interruptedCall)

    /// React to the phone-call state from the CXCallObserver. A connected or
    /// dialing call during a live session parks it in `.interruptedCall`; the
    /// call ending restores exactly the captured state. Everything else
    /// no-ops, so a call while idle/paused/summary never touches the session.
    func handleCallChange(callEnded: Bool) {
        if callEnded {
            guard case let .interruptedCall(previousState) = sessionState else {
                return
            }
            restore(previousState)
            HapticManager.notification(.warning)
        } else {
            guard sessionState.isActive, let previousState = capturePausedFromState() else {
                return
            }
            // §2 fix — same capture pause() does, so a call arriving mid-rest
            // restores the rest timer instead of leaving it dead at 0:00.
            pausedRestRemaining = captureRestRemainingBeforeStop()
            stopRestTimer()
            stopWarmupMoveTimer()
            stopElapsedTimer()
            sessionState = .interruptedCall(previousState: previousState)
        }
    }

    func startCallMonitoring() {
        guard callMonitor == nil else {
            return
        }
        let monitor = CallInterruptionMonitor()
        monitor.onCallChange = { [weak self] ended in
            self?.handleCallChange(callEnded: ended)
        }
        callMonitor = monitor
    }

    func stopCallMonitoring() {
        callMonitor = nil
    }
}

// MARK: - CallInterruptionMonitor

/// NSObject shim between CXCallObserver and the @Observable view-model
/// (which can't be an NSObject delegate itself). Forwards only what the
/// session cares about: a call becoming live, or ending. Delegate callbacks
/// arrive on the main queue, so hopping to the main actor is assumption-safe.
/// Internal (not private) — `TrainingViewModel.callMonitor`'s stored-property
/// type must be visible from the main file too.
@MainActor
final class CallInterruptionMonitor: NSObject, CXCallObserverDelegate {
    private let observer = CXCallObserver()
    /// `true` = the call ended.
    var onCallChange: ((Bool) -> Void)?

    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }

    nonisolated func callObserver(_: CXCallObserver, callChanged call: CXCall) {
        let ended = call.hasEnded
        MainActor.assumeIsolated {
            onCallChange?(ended)
        }
    }
}
