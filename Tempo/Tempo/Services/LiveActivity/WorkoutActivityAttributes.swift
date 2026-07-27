//
// WorkoutActivityAttributes.swift
// Tempo
//
// §3.9 workout Live Activity — the shared ActivityAttributes type. Referenced
// by BOTH targets (the app's WorkoutActivityManager and the widget's
// WorkoutLiveActivity), so project.yml lists this file in the TempoWidget
// sources too, exactly like FocusTimerActivityAttributes.
//

import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "PUSH", "PULL", … — the day's workout type label.
        var workoutType: String
        /// Current exercise ("Barbell Bench Press"), or "Warm-Up" during the
        /// guided block.
        var exerciseName: String
        /// "Set 2 of 4" style position within the current exercise.
        var setText: String
        /// Whole-session working-set progress for the bar.
        var completedSets: Int
        var totalSets: Int
        /// Resting: the widget renders a live countdown to `restEndsAt`.
        var isResting: Bool
        var restEndsAt: Date?
        /// Session clock anchor (nil until the first working set).
        var startedAt: Date?
        /// Paused or parked behind a phone call.
        var isPaused: Bool
    }

    /// The WorkoutPlan this session belongs to.
    var planID: String
}
