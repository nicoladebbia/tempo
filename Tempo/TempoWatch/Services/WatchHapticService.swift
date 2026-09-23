//
// WatchHapticService.swift
// Tempo
//
// Created by Tempo on 3/25/26.
//
//

import WatchKit

// MARK: - Watch Haptic Service

// Per APPLE_WATCH_APP.md Section 4 — Haptic pattern definitions.

enum WatchHapticService {
    static func playSetComplete() {
        WKInterfaceDevice.current().play(.success)
    }

    static func playRestTimerEnd() {
        WKInterfaceDevice.current().play(.notification)
    }

    static func playFocusTimerEnd() {
        WKInterfaceDevice.current().play(.directionUp)
    }

    static func playWorkoutStart() {
        WKInterfaceDevice.current().play(.start)
    }

    static func playWorkoutEnd() {
        WKInterfaceDevice.current().play(.stop)
    }

    static func playNonNegotiableComplete() {
        WKInterfaceDevice.current().play(.click)
    }

    static func playError() {
        WKInterfaceDevice.current().play(.failure)
    }

    static func playMealLogged() {
        WKInterfaceDevice.current().play(.success)
    }

    /// Action sent while unreachable (queued via `transferUserInfo`, not yet
    /// confirmed by the phone) or acknowledged-but-not-applied. Distinct
    /// from `playError` — nothing failed, it just isn't confirmed yet.
    static func playQueued() {
        WKInterfaceDevice.current().play(.click)
    }
}
