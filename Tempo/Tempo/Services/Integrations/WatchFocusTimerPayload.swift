//
// WatchFocusTimerPayload.swift
// Tempo
//
// Focus timer mode — the real session state the Watch mirrors from the
// phone, same channel/shape as `WatchWorkoutPayload` (§21) and
// `GuidedRunActivitySnapshot`. Shared between BOTH targets: the phone's
// `PhoneWatchConnectivityService` encodes it into the WCSession application
// context under `contextKey`; the watch's `WatchConnectivityService` decodes
// it. project.yml lists this file in the TempoWatch sources too.
//
// Without this, a focus session started on the PHONE was invisible to the
// Watch app (its Focus Timer tab always showed its own local, phone-unaware
// ready/running state — Watch audit, 2026-09). This payload lets the Watch
// adopt an in-progress phone session and stop ticking a phantom one once the
// phone ends it.
//

import Foundation

struct WatchFocusTimerPayload: Codable, Equatable {
    var isPaused: Bool
    /// Seconds left in the CURRENT phase (focus or break) as of `updatedAt`.
    /// A snapshot, not a live value — the Watch keeps its own local
    /// second-by-second countdown ticking from this starting point exactly
    /// like a wrist-started session already does, rather than polling.
    var remainingSeconds: TimeInterval
    /// "FOCUS TIME" / "BREAK" / "LONG BREAK" — mirrors the Live Activity's
    /// own phase label.
    var phaseLabel: String
    /// 1-based session index, e.g. 2.
    var sessionIndex: Int
    var totalSessions: Int
    var updatedAt: Date

    /// Application-context key this payload travels under.
    static let contextKey = "focusTimer"
    /// Same convention as `GuidedRunActivitySnapshot.endedKey` — an ABSENT
    /// context key means "unchanged", not "cleared", so ending the session
    /// needs its own explicit flag the Watch can distinguish from silence.
    static let endedKey = "focusTimerEnded"

    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return dict
    }

    static func from(dictionary: [String: Any]) -> WatchFocusTimerPayload? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        return try? JSONDecoder().decode(WatchFocusTimerPayload.self, from: data)
    }
}
