//
// WatchTimerState.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - Watch Timer State

// Per APPLE_WATCH_APP.md — Focus timer state for Pomodoro on Watch.

struct WatchTimerState {
    var isRunning: Bool = false
    var isPaused: Bool = false
    var totalSeconds: Int = 1500 // 25min default
    var remainingSeconds: Int = 1500
    var sessionCount: Int = 0
}
