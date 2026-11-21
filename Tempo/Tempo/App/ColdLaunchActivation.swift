//
// ColdLaunchActivation.swift
// Tempo
//
// On a cold launch SwiftUI reports scenePhase → .active right after the launch
// `.task` has already rebuilt the reminders. Foreground handlers use this to skip
// that one activation: two rebuilds at once can cancel each other's reminders.
// Only the FIRST activation, and only shortly after launch, counts, so a real
// return from the background is never skipped even if the launch one never fired.
//

import Foundation

struct ColdLaunchActivation {
    /// Wider than any launch, far shorter than a real background → foreground trip.
    static let window: TimeInterval = 10

    private let launchedAt: Date
    private var seenActivation = false

    init(launchedAt: Date = Date()) {
        self.launchedAt = launchedAt
    }

    /// Call on every `.active`. True only for the launch activation.
    mutating func isColdLaunch(now: Date = Date()) -> Bool {
        defer { seenActivation = true }
        return !seenActivation && now.timeIntervalSince(launchedAt) < Self.window
    }
}
