import Foundation

// MARK: - Watch Snapshot
// Per APPLE_WATCH_APP.md Section 1.3 — Lightweight daily data from iPhone.
// Per XCODE_PROJECT_STRUCTURE.md Section 11.6 — Watch receives lightweight snapshot, no SwiftData.

struct WatchSnapshot: Codable {
    let dailyScore: Int
    let recoveryZone: String
    let recoveryScore: Int
    let sleepHours: Double
    let hrv: Double
    let rhr: Int
    let nextTaskName: String
    let nextTaskTimeRemaining: String
    let nnCompleted: Int
    let nnTotal: Int
    let leisureUnlocked: Bool
    let currentStreak: Int
    let xp: Int
    let leaderboardPosition: Int?
    let updatedAt: Date

    static let placeholder = WatchSnapshot(
        dailyScore: 78,
        recoveryZone: "green",
        recoveryScore: 72,
        sleepHours: 7.2,
        hrv: 68.3,
        rhr: 52,
        nextTaskName: "Study",
        nextTaskTimeRemaining: "1h23m",
        nnCompleted: 3,
        nnTotal: 5,
        leisureUnlocked: false,
        currentStreak: 12,
        xp: 4200,
        leaderboardPosition: 3,
        updatedAt: .now
    )

    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    static func from(dictionary: [String: Any]) -> WatchSnapshot? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
}
