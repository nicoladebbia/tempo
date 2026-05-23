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

    // Returns "" when no refresh ID is set so log lines outside a refresh
    // cycle stay clean. Inside one, returns "[T:abc123] ".
    static var prefix: String {
        guard let id = refreshID else { return "" }
        return "[T:\(id)] "
    }
}
