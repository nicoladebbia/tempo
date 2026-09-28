//
// LiveActivityLaunchCleanup.swift
// Tempo
//
// A fresh process's three activity managers (`WorkoutActivityManager`,
// `FocusTimerActivityManager`, `GuidedRunActivityManager`) all start with
// `current == nil`. But ActivityKit's `Activity`s are OS-managed and outlive
// the process that requested them — if the app is force-quit, crashes, or is
// killed by the system mid-session, the Live Activity it started keeps
// showing on the lock screen with no in-memory reference left to end it.
// With no cleanup, that Activity is a permanent-looking zombie until its own
// stale window or ActivityKit's 4-hour cap finally clears it.
//
// Call `LiveActivityLaunchCleanup.endOrphanedActivities()` once, early at
// launch (before any session-resume UI could plausibly request a fresh
// Activity of its own) — any real resume flow re-requests a brand-new
// Activity afterwards, so ending everything ActivityKit still has for these
// three attribute types is always safe, never a false positive.
//

import ActivityKit

enum LiveActivityLaunchCleanup {
    static func endOrphanedActivities() async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for activity in Activity<FocusTimerActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for activity in Activity<GuidedRunActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
