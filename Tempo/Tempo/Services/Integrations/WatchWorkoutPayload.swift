//
// WatchWorkoutPayload.swift
// Tempo
//
// §21 — the real workout data the Watch runs on (replacing its hardcoded
// "Bench Press 4×8@80" stubs). Shared between BOTH targets: the phone's
// PhoneWatchConnectivityService encodes it into the WCSession application
// context under the "workout" key; the watch's WatchConnectivityService
// decodes it. project.yml lists this file in the TempoWatch sources too,
// exactly like the Live Activity attributes are shared with TempoWidget.
//

import Foundation

struct WatchWorkoutPayload: Codable, Equatable {
    struct Exercise: Codable, Equatable {
        let name: String
        /// Working sets only — the watch never runs the warm-up ramp.
        let totalSets: Int
        let completedSets: Int
        let targetReps: Int
        let targetWeightKg: Double
    }

    /// "PUSH", "PULL", … display label for the ready screen.
    let workoutType: String
    /// yyyy-MM-dd of the plan's day — the watch ignores stale contexts.
    let dayKey: String
    /// "kg" / "lbs" — weights stay canonical kg on the wire; the watch
    /// converts for display so the wrist matches the phone's unit.
    let unit: String
    let exercises: [Exercise]
    let updatedAt: Date

    /// Application-context key this payload travels under.
    static let contextKey = "workout"

    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return dict
    }

    static func from(dictionary: [String: Any]) -> WatchWorkoutPayload? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        return try? JSONDecoder().decode(WatchWorkoutPayload.self, from: data)
    }
}
