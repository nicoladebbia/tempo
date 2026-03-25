import Foundation

// MARK: - XPSource

enum XPSource: String, Codable, CaseIterable, Sendable {
    case workout
    case study
    case meal
    case sleep
    case steps
    case nonNegotiable = "non_negotiable"
    case streak
    case challenge
    case achievement
    case perfectDay = "perfect_day"
    case penalty
}

// MARK: - AchievementCategory

enum AchievementCategory: String, Codable, CaseIterable, Sendable {
    case training
    case study
    case nutrition
    case recovery
    case consistency
    case social
    case milestone
    case hidden
}

// MARK: - AchievementRarity

enum AchievementRarity: String, Codable, CaseIterable, Sendable {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    var xpMultiplier: Double {
        switch self {
        case .common: 1.0
        case .uncommon: 1.5
        case .rare: 2.0
        case .epic: 3.0
        case .legendary: 5.0
        }
    }
}
