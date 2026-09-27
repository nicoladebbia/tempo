//
// SafeTimerRange.swift
// TempoWidget
//
// `Text(timerInterval:)` traps when its range is inverted. A Live Activity's
// end date is a snapshot pushed by the app, so by the time the widget renders
// "now" can already be past it — one stale activity crashed the whole widget
// process (taking every other Live Activity down with it). Capture "now" once
// and clamp, so a countdown that already ended just shows 0:00.
//

import Foundation

enum SafeTimerRange {
    static func countdown(to end: Date, now: Date = Date()) -> ClosedRange<Date> {
        now ... max(now, end)
    }
}
