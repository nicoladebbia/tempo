//
// FocusTimerActivityAttributes.swift
// Tempo
//
// Created by Tempo on 09/05/2026.
//
//

import ActivityKit
import Foundation

struct FocusTimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Wall-clock instant the current phase ends. Used so the system text
        /// timer can update once per second without app churn.
        var phaseEndsAt: Date
        /// "FOCUS TIME", "BREAK TIME", "PAUSED" — short uppercase phase label.
        var phaseLabel: String
        /// 0.0–1.0, used by the Dynamic Island ring view.
        var progress: Double
        /// Subject tag (e.g., "Calculus II") or nil if untagged.
        var subject: String?
        /// 1-based session index e.g. 2.
        var sessionIndex: Int
        /// Total planned sessions e.g. 4.
        var totalSessions: Int
        /// Whether the timer is currently paused.
        var isPaused: Bool
    }

    /// Static identifier for the activity instance — useful for telemetry.
    var sessionID: String
}
