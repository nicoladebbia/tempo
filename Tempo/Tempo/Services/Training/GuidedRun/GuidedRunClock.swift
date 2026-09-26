//
// GuidedRunClock.swift
// Tempo
//
// Guided run mode — `GuidedRunSession` is date-based, never tick-counted: it
// reads `clock.now()` on every `tick()` and re-derives elapsed/remaining
// time from stored `Date`s, so it survives backgrounding and screen lock
// (no drift, no lost ticks) and is fully unit-testable with a fake clock
// (TempoTests/Services/GuidedRun/FakeGuidedRunClock.swift).
//

import Foundation

// MARK: - GuidedRunClock

protocol GuidedRunClock: Sendable {
    func now() -> Date
}

// MARK: - SystemClock

struct SystemClock: GuidedRunClock {
    func now() -> Date {
        Date()
    }
}

// MARK: - ScaledSystemClock

/// Speeds up elapsed wall-clock time by `scale`x — used only when launched
/// with `--uitesting-time-scale=<N>` (GuidedRunView.testClock), so a UI test
/// can screenshot countdown/work/rest/summary without waiting real minutes
/// for a "35 continuous" duration step.
final class ScaledSystemClock: GuidedRunClock, @unchecked Sendable {
    private let scale: Double
    private let virtualOrigin: Date
    private let realOrigin: Date

    init(scale: Double, referenceDate: Date = Date()) {
        self.scale = max(1, scale)
        virtualOrigin = referenceDate
        realOrigin = Date()
    }

    func now() -> Date {
        let realElapsed = Date().timeIntervalSince(realOrigin)
        return virtualOrigin.addingTimeInterval(realElapsed * scale)
    }
}
