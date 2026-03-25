import Foundation

// MARK: - Watch Quick Action
// Per APPLE_WATCH_APP.md — Actions sent from Watch back to iPhone.

enum WatchQuickAction: String, Codable {
    case markNonNegotiableDone
    case logSet
    case startFocusTimer
    case stopFocusTimer
    case pauseFocusTimer
    case markMealEaten
    case startWorkout
    case endWorkout
}

struct WatchActionPayload: Codable {
    let action: WatchQuickAction
    let payload: [String: String]
}
