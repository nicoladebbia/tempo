//
// GuidedRunActivityManager.swift
// Tempo
//
// Guided run mode — app-side lifecycle for the guided-run Live Activity.
// Same shape as WorkoutActivityManager/FocusTimerActivityManager: request at
// session start, update on every meaningful transition (GuidedRunLiveCoordinator
// decides when — phase/pause changes and the engine's own cue moments), end
// on finish/discard. All calls no-op when Live Activities are disabled or
// none is running.
//
// `start()` is `async` and AWAITS its own teardown of a stale activity
// inline, rather than firing a separate detached task and racing ahead of it
// (code review finding: a late-resolving detached end() could otherwise clear
// the brand-new activity this method just assigned to `current`). Actual
// serialization of every call into this manager — so two calls never touch
// `current` concurrently, and updates apply in the order they were queued
// rather than completion order — is the caller's job:
// `GuidedRunLiveCoordinator.enqueueActivityWork` chains every start/update/end
// onto one another. (A plain class, not an `actor`, because `Activity<T>`'s
// own `update`/`end` are not `Sendable`-friendly across an actor boundary —
// matches the existing siblings' shape.)
//

import ActivityKit
import Foundation
import os

final class GuidedRunActivityManager: @unchecked Sendable {
    static let shared = GuidedRunActivityManager()

    private let logger = Logger(subsystem: "app.tempo", category: "LiveActivity")
    private var current: Activity<GuidedRunActivityAttributes>?

    private init() {}

    func start(runTitle: String, state: GuidedRunActivitySnapshot) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }
        // Awaited inline — the caller (GuidedRunLiveCoordinator) serializes
        // every call into this manager, so this always fully tears down any
        // stale activity before requesting the new one, never racing a
        // separately-scheduled teardown from a prior call.
        await endCurrent()

        let attributes = GuidedRunActivityAttributes(runTitle: runTitle)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Self.staleDate(for: state))
            )
            current = activity
        } catch {
            logger.error("Failed to start guided run Live Activity: \(error.localizedDescription)")
        }
    }

    func update(state: GuidedRunActivitySnapshot) async {
        guard let activity = current else {
            return
        }
        await activity.update(.init(state: state, staleDate: Self.staleDate(for: state)))
    }

    func endCurrent() async {
        guard let activity = current else {
            return
        }
        await activity.end(nil, dismissalPolicy: .immediate)
        current = nil
    }

    /// Countdown/work count up with no natural end; rest counts down to a
    /// known instant — go stale shortly after that, else a generous window
    /// so an ordinary rep/round doesn't need constant refreshing.
    private static func staleDate(for state: GuidedRunActivitySnapshot) -> Date {
        if state.countsDown {
            return state.timerAnchor.addingTimeInterval(120)
        }
        return Date().addingTimeInterval(30 * 60)
    }
}
