//
// WatchQuickAction.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
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

    /// §11 — unique per send, so the phone-side `WatchActionRouter` can
    /// recognize (and ignore) a duplicate delivery of the exact same action:
    /// WCSession can redeliver a queued `transferUserInfo` transfer, and a
    /// lost ack can leave the watch retrying. Defaulted so every existing
    /// `WatchActionPayload(action:payload:)` call site needs no change —
    /// each construction still gets its own fresh id.
    var id: String = UUID().uuidString

    init(action: WatchQuickAction, payload: [String: String]) {
        self.action = action
        self.payload = payload
    }

    /// Actions queued by an older watch build carry no `id` — decode them
    /// with a fresh one (prefer the payload's `actionID` tag) instead of
    /// dropping them as undecodable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(WatchQuickAction.self, forKey: .action)
        payload = try container.decode([String: String].self, forKey: .payload)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? payload["actionID"]
            ?? UUID().uuidString
    }
}
