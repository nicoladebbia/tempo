import Foundation
import Vapor

// MARK: - Server clock

//
// "Now" for business logic (what day it is, which week, whether a subscription
// has lapsed, when a job should fire). Always the real time, except on the
// local test server, where `scripts/testenv.sh time` can move it to test
// Sundays, mornings or an expired trial without waiting. Security clocks
// (JWT expiry, rate limits, caches) stay on the real time on purpose.

extension Application {
    var now: Date {
        Date().addingTimeInterval(testMode?.clockOffset ?? 0)
    }
}

extension Request {
    var now: Date {
        application.now
    }
}
