//
// WatchQuickAction.swift
// Tempo
//
// Created by Tempo on 3/25/26.
//
//

import Foundation

// MARK: - WatchQuickAction

// Per APPLE_WATCH_APP.md — Actions sent from Watch back to iPhone.

enum WatchQuickAction: String, Codable {
    case markNonNegotiableDone
    case logSet
    case startFocusTimer
    case stopFocusTimer
    case pauseFocusTimer
    case resumeFocusTimer
    case markMealEaten
    case startWorkout
    // §22 — `.endWorkout` was removed: there is no honest phone-side
    // equivalent that doesn't reach into ActiveWorkoutView's set-completion
    // internals (ExerciseHistory + per-set feedback aggregation, owned by
    // the Training surface). The watch's own "ALL SETS DONE" screen already
    // reflects reality once the last `.logSet` syncs back down — see
    // WorkoutView.swift.
}

// MARK: - WatchActionPayload

struct WatchActionPayload: Codable {
    let action: WatchQuickAction
    let payload: [String: String]
}
