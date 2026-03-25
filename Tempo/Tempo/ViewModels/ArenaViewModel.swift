import Foundation
import SwiftUI
import SwiftData

// MARK: - Arena Load State

enum ArenaLoadState: Sendable {
    case loading
    case loaded
    case error(String)
}

// MARK: - Arena ViewModel
// Per MODULE_ARENA.md Sections 5-12 and BUILD_PLAN.md Step 14.3.

@Observable
@MainActor
final class ArenaViewModel {

    // MARK: - State

    var loadState: ArenaLoadState = .loading

    // XP / Level
    var todayXP: Int = 0
    var totalXP: Int = 0
    var level: Int = 1
    var levelTitle: String = "Rookie"
    var xpProgress: Double = 0
    var xpForNextLevel: Int = 100
    var streakDays: Int = 0
    var streakMultiplier: Double = 1.0

    // XP Breakdown
    var xpBreakdown: [XPBreakdownRow] = []

    // Leaderboard
    var leaderboardPreview: [LeaderboardEntry] = []
    var myRank: Int = 0
    var gapToFirst: Int = 0

    // Friends
    var friendCount: Int = 0
    var pendingRequestCount: Int = 0

    // Challenges
    var activeChallenges: [ChallengeLocal] = []

    // Achievements
    var recentAchievements: [Achievement] = []
    var totalEarned: Int = 0

    // Detail sheet
    var showXPDetail: Bool = false

    // MARK: - Dependencies

    private let xpEngine: any XPEngineProtocol

    init(xpEngine: any XPEngineProtocol) {
        self.xpEngine = xpEngine
    }

    // MARK: - Load

    func load(
        xpEvents: [XPEvent],
        achievements: [Achievement],
        challenges: [ChallengeLocal],
        userTotalXP: Int,
        userStreakDays: Int
    ) {
        // XP calculations
        let today = Calendar.current.startOfDay(for: Date())
        let todayEvents = xpEvents.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }

        self.todayXP = todayEvents.reduce(0) { $0 + $1.amount }
        self.totalXP = userTotalXP
        self.level = xpEngine.currentLevel(totalXP: userTotalXP)
        self.levelTitle = Self.levelTitle(for: level)
        self.xpForNextLevel = xpEngine.xpToNextLevel(totalXP: userTotalXP)
        self.streakDays = userStreakDays
        self.streakMultiplier = 1.0 + min(0.50, Double(userStreakDays) * 0.02)

        // XP progress bar
        let thresholds = Self.levelThresholds
        let currentLevelXP = thresholds[safe: level - 1] ?? 0
        let nextLevelXP = thresholds[safe: level] ?? currentLevelXP
        let range = max(1, nextLevelXP - currentLevelXP)
        self.xpProgress = Double(userTotalXP - currentLevelXP) / Double(range)

        // XP breakdown by source
        let grouped = Dictionary(grouping: todayEvents, by: { $0.source })
        self.xpBreakdown = XPSource.allCases.map { source in
            let events = grouped[source] ?? []
            let total = events.reduce(0) { $0 + $1.amount }
            return XPBreakdownRow(source: source, xp: total, count: events.count)
        }.filter { $0.xp != 0 }

        // Challenges
        self.activeChallenges = challenges.filter { $0.isActive && !$0.hasEnded }

        // Achievements
        self.recentAchievements = achievements
            .filter { $0.isEarned }
            .sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) }
            .prefix(3)
            .map { $0 }
        self.totalEarned = achievements.filter { $0.isEarned }.count

        self.loadState = .loaded
    }

    // MARK: - Level Thresholds
    // Per MODULE_ARENA.md Section 3.1 — Formula: floor(200 * N^1.65)

    static let levelThresholds: [Int] = {
        var thresholds = [0]
        for n in 1...50 {
            thresholds.append(Int(floor(200.0 * pow(Double(n), 1.65))))
        }
        return thresholds
    }()

    static func levelTitle(for level: Int) -> String {
        switch level {
        case 1...5: return "Rookie"
        case 6...10: return "Contender"
        case 11...15: return "Warrior"
        case 16...20: return "Gladiator"
        case 21...25: return "Centurion"
        case 26...30: return "Captain"
        case 31...35: return "Commander"
        case 36...40: return "Titan"
        case 41...45: return "Warlord"
        case 46...50: return "Legend"
        default: return "Rookie"
        }
    }
}

// MARK: - Supporting Types

struct XPBreakdownRow: Identifiable {
    let id = UUID()
    let source: XPSource
    let xp: Int
    let count: Int

    var emoji: String {
        switch source {
        case .workout: return "🏋️"
        case .study: return "📖"
        case .meal: return "🍴"
        case .sleep: return "🌙"
        case .steps: return "🦶"
        case .nonNegotiable: return "✓"
        case .streak: return "🔥"
        case .challenge: return "⚔️"
        case .achievement: return "🏅"
        case .perfectDay: return "⭐"
        case .penalty: return "⚠️"
        }
    }

    var label: String {
        switch source {
        case .workout: return "Workout"
        case .study: return "Study"
        case .meal: return "Meals"
        case .sleep: return "Sleep"
        case .steps: return "Steps"
        case .nonNegotiable: return "Tasks"
        case .streak: return "Streak"
        case .challenge: return "Challenge"
        case .achievement: return "Achievement"
        case .perfectDay: return "Perfect Day"
        case .penalty: return "Penalty"
        }
    }
}

struct LeaderboardEntry: Identifiable {
    let id = UUID()
    let rank: Int
    let username: String
    let displayName: String
    let xp: Int
    let level: Int
    let isMe: Bool
}

// MARK: - Collection Safe Access

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
