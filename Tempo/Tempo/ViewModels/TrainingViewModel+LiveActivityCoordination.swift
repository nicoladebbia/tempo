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
    var hasActiveLiveSession: Bool {
        sessionState.isActive
    }

    /// Ends the on-screen Activity for a higher-priority one, leaving
    /// `sessionState` (the actual workout) untouched.
    func suspendLiveActivity() async {
        await WorkoutActivityManager.shared.endCurrent()
    }

    /// Rebuilds the Activity from current session state — safe to call any
    /// time; no-ops once the workout itself is no longer active.
    func resumeLiveActivityIfNeeded() async {
        guard sessionState.isActive, let plan = todayPlan, let state = liveActivityState() else {
            return
        }
        WorkoutActivityManager.shared.start(planID: plan.id.uuidString, state: state)
    }
}
