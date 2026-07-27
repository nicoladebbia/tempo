//
// WorkoutActivityManager.swift
// Tempo
//
// §3.9 — app-side lifecycle for the workout Live Activity. Same shape as
// FocusTimerActivityManager: request on session start, update on every
// state transition (driven by TrainingViewModel.sessionState's didSet),
// end immediately on summary/discard. All calls no-op when Live Activities
// are disabled or none is running.
//

import ActivityKit
import Foundation
import os

final class WorkoutActivityManager: @unchecked Sendable {
    static let shared = WorkoutActivityManager()

    private let logger = Logger(subsystem: "app.tempo", category: "LiveActivity")
    private var current: Activity<WorkoutActivityAttributes>?

    private init() {}

    func start(planID: String, state: WorkoutActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }
        // Tear down any stale activity before requesting a new one.
        endCurrentDetached()

        let attributes = WorkoutActivityAttributes(planID: planID)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Self.staleDate(for: state))
            )
            current = activity
        } catch {
            logger.error("Failed to start workout Live Activity: \(error.localizedDescription)")
        }
    }

    func update(state: WorkoutActivityAttributes.ContentState) async {
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

    /// Synchronous fire-and-forget for callsites that aren't async.
    func endCurrentDetached() {
        Task {
            await self.endCurrent()
        }
    }

    /// A workout has no natural end date; go stale a while after the last
    /// transition (or shortly after the rest countdown finishes).
    private static func staleDate(for state: WorkoutActivityAttributes.ContentState) -> Date {
        if let rest = state.restEndsAt {
            return rest.addingTimeInterval(120)
        }
        return Date().addingTimeInterval(30 * 60)
    }
}
