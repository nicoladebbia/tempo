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
    case markMealEaten
    case startWorkout
    case endWorkout
}

// MARK: - WatchActionPayload

struct WatchActionPayload: Codable {
    let action: WatchQuickAction
    let payload: [String: String]
}
