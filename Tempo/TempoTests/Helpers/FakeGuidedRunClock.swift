//
// FakeGuidedRunClock.swift
// Tempo
//
// Guided run mode — a settable clock for GuidedRunSessionTests. Advancing
// it simulates real elapsed time without the test ever sleeping.
//

import Foundation
@testable import Tempo

final class FakeGuidedRunClock: GuidedRunClock, @unchecked Sendable {
    var current: Date

    init(current: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = current
    }

    func now() -> Date {
        current
    }

    func advance(_ seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}
