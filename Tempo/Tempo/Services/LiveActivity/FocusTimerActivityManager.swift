//
// FocusTimerActivityManager.swift
// Tempo
//
// Created by Tempo on 09/05/2026.
//
//

import ActivityKit
import Foundation
import os

final class FocusTimerActivityManager: @unchecked Sendable {
    static let shared = FocusTimerActivityManager()

    private let logger = Logger(subsystem: "app.tempo", category: "LiveActivity")
    private var current: Activity<FocusTimerActivityAttributes>?

    private init() {}

    func start(
        sessionID: String,
        phaseEndsAt: Date,
        phaseLabel: String,
        progress: Double,
        subject: String?,
        sessionIndex: Int,
        totalSessions: Int
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }
        // Tear down any stale activity before requesting a new one.
        endCurrentDetached()

        let attributes = FocusTimerActivityAttributes(sessionID: sessionID)
        let state = FocusTimerActivityAttributes.ContentState(
            phaseEndsAt: phaseEndsAt,
            phaseLabel: phaseLabel,
            progress: progress,
            subject: subject,
            sessionIndex: sessionIndex,
            totalSessions: totalSessions,
            isPaused: false
        )
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: phaseEndsAt.addingTimeInterval(60))
            )
            current = activity
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    func update(
        phaseEndsAt: Date,
        phaseLabel: String,
        progress: Double,
        sessionIndex: Int,
        totalSessions: Int,
        isPaused: Bool
    ) async {
        guard let activity = current else {
            return
        }
        let state = FocusTimerActivityAttributes.ContentState(
            phaseEndsAt: phaseEndsAt,
            phaseLabel: phaseLabel,
            progress: progress,
            subject: nil,
            sessionIndex: sessionIndex,
            totalSessions: totalSessions,
            isPaused: isPaused
        )
        let staleDate = phaseEndsAt.addingTimeInterval(60)
        await activity.update(.init(state: state, staleDate: staleDate))
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
}
