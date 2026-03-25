import Foundation

// MARK: - Watch Workout State
// Per APPLE_WATCH_APP.md — Current workout + set tracking on Watch.

struct WatchWorkoutState {
    var isActive: Bool = false
    var exerciseName: String = ""
    var currentSet: Int = 0
    var totalSets: Int = 0
    var lastWeight: Double = 0
    var lastReps: Int = 0
    var restTimerSeconds: Int = 0
    var elapsedSeconds: Int = 0
}
