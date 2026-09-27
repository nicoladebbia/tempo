//
// GuidedRunActivitySnapshot.swift
// Tempo
//
// Guided run mode — the single data snapshot that drives BOTH the Live
// Activity (`GuidedRunActivityAttributes.ContentState`, TempoWidget) and the
// Apple Watch mirror (`WatchConnectivityService.latestGuidedRun`). Built once
// per meaningful state change by `GuidedRunActivityContentBuilder` and fanned
// out to both consumers so they never drift from each other.
//
// Deliberately Foundation-only (no ActivityKit — unavailable on watchOS) so
// project.yml can list this ONE file in all three targets: Tempo, TempoWidget
// and TempoWatch, exactly like `WatchWorkoutPayload` is already shared
// between Tempo and TempoWatch.
//

import Foundation

struct GuidedRunActivitySnapshot: Codable, Hashable {
    /// "Shuttle 1 · Rep 2/4", "Fartleck · In progress" — the current step.
    var stepTitle: String
    /// "Cap 0:58", "Target 5 km" — nil when the step has nothing to show.
    var detailText: String?
    /// Rest only — "Next: Rep 3" preview of what's coming up.
    var nextStepText: String?
    /// Continuous (duration/distance) steps only.
    var distanceText: String?
    var paceText: String?
    /// Live from the paired Watch's HKWorkoutSession — nil with no Watch.
    var heartRateText: String?
    var heartRateZone: Int?
    var isRest: Bool
    var isCountdown: Bool
    var isPaused: Bool
    /// true → the widget/watch count DOWN to `timerAnchor`; false → count UP
    /// from it (open-ended — `Text(timerInterval:countsDown:)` handles both
    /// with no per-second push).
    var countsDown: Bool
    /// Countdown/rest: the GO/rest-end instant. Work: the step's own start
    /// instant, elapsed-adjusted so a late-attached viewer is still exact.
    var timerAnchor: Date
    /// Paused sessions freeze on this literal text instead of a live timer —
    /// nothing ticks while `isPaused`.
    var frozenText: String?
    var updatedAt: Date

    /// Wire key both `PhoneWatchConnectivityService.pushGuidedRun` and
    /// `WatchConnectivityService.ingestGuidedRun` key the application
    /// context / message dictionary under.
    static let contextKey = "guidedRun"
    /// Explicit "session over" signal — a nil `latestGuidedRun` on the watch
    /// can't be expressed via application context (an absent key just means
    /// "keep whatever we had"), so ending the run sends this flag instead.
    static let endedKey = "guidedRunEnded"

    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return dict
    }

    static func from(dictionary: [String: Any]) -> GuidedRunActivitySnapshot? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        return try? JSONDecoder().decode(GuidedRunActivitySnapshot.self, from: data)
    }
}
