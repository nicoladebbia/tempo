//
// TrainingViewModel+LiveActivityCoordination.swift
// Tempo
//
// `LiveActivityParticipant` conformance for the gym-workout Live Activity —
// split out of TrainingViewModel.swift to keep that file under the
// file-length lint cap. See `LiveActivityCoordinator` for how suspend/resume
// fits into the priority scheme against the focus timer and guided run.
//

import Foundation

extension TrainingViewModel: LiveActivityParticipant {
    /// Deliberately NOT `sessionState.isActive` — that's `false` for
    /// `.paused`/`.interruptedCall` (see `WorkoutSessionState.isActive`),
    /// which used to mean a workout paused at the moment a higher-priority
    /// activity suspended it could NEVER be resumed: `end(_:)` would see
    /// `hasActiveLiveSession == false`, drop `.gymWorkout` from
    /// `suspendedKinds` for good, and unpausing afterwards only ever routes
    /// through `syncLiveActivity()` → `LiveActivityCoordinator.update`,
    /// which no-ops once `current` is nil (code review finding). Whether
    /// there is something to resume is exactly whether `liveActivityState()`
    /// would build a snapshot — which already returns non-nil (correctly
    /// `isPaused: true`) for a paused session — so defer to it directly
    /// instead of a second, narrower definition of "alive".
    var hasActiveLiveSession: Bool {
        liveActivityState() != nil
    }

    /// Ends the on-screen Activity for a higher-priority one, leaving
    /// `sessionState` (the actual workout) untouched.
    func suspendLiveActivity() async {
        await WorkoutActivityManager.shared.endCurrent()
    }

    /// Rebuilds the Activity from current session state — safe to call any
    /// time; no-ops once the workout itself is no longer active. Correctly
    /// re-requests a PAUSED-looking Activity when resumed mid-pause, since
    /// `liveActivityState()` itself carries `isPaused`.
    func resumeLiveActivityIfNeeded() async {
        guard let plan = todayPlan, let state = liveActivityState() else {
            return
        }
        WorkoutActivityManager.shared.start(planID: plan.id.uuidString, state: state)
    }
}
