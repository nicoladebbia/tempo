import Foundation

// Task-local correlation IDs so a single refresh cycle's log lines can be
// grouped at a glance. Without this, three Whoop fetches in two minutes look
// identical in the console and you can't tell whether they were three distinct
// triggers or one trigger triple-firing.
//
// Usage at the trigger boundary (e.g. DashboardViewModel.refresh):
//
//     await DebugTrace.$refreshID.withValue(DebugTrace.newID()) {
//         // … all the awaited work in this refresh cycle …
//     }
//
// All downstream log helpers just call `DebugTrace.prefix` and prepend it.
enum DebugTrace {
    @TaskLocal static var refreshID: String?

    static func newID() -> String {
        String(UUID().uuidString.prefix(6))
    }

    // Monotonic reference captured at first access (≈ process launch). Used to
    // stamp every traced log line with milliseconds-since-launch so the gaps
    // between Whoop fetch "rounds" are measurable from the console — the only
    // way to tell a concurrent-in-flight duplicate (gap ≈ 0) apart from a
    // genuine TTL-expired re-fetch (gap > 30s) across slow tab navigation.
    private static let launchClock = ContinuousClock.now

    static var elapsedMs: Int {
        Int(launchClock.duration(to: .now) / .milliseconds(1))
    }

    // Returns "[+1234ms] " when outside a refresh cycle, "[+1234ms T:abc123] "
    // inside one. The launch-elapsed stamp is always present so every line is
    // time-orderable; the refresh ID groups one cycle's lines together.
    static var prefix: String {
        let t = "+\(elapsedMs)ms"
        guard let id = refreshID else { return "[\(t)] " }
        return "[\(t) T:\(id)] "
    }
}
