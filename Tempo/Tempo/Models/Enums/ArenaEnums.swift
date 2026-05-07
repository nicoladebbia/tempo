//
// ArenaEnums.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftUI

// MARK: - XPSource

enum XPSource: String, Codable, CaseIterable {
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
    case earlyBird = "early_bird"
}

// MARK: - AchievementCategory

enum AchievementCategory: String, Codable, CaseIterable {
    case training
    case study
    case nutrition
    case recovery
    case consistency
    case social
    case milestone
    case hidden
}

// MARK: - League

enum League: String, Codable, CaseIterable {
    case bronze
    case silver
    case gold
    case diamond
    case champion

    var displayName: String {
        rawValue.capitalized
    }

    var iconName: String {
        switch self {
        case .bronze: "shield.fill"
        case .silver: "shield.fill"
        case .gold: "shield.fill"
        case .diamond: "suit.diamond.fill"
        case .champion: "crown.fill"
        }
    }

    var color: Color {
        switch self {
        case .bronze: Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver: Color(red: 0.75, green: 0.75, blue: 0.80)
        case .gold: Color(red: 1.0, green: 0.84, blue: 0.0)
        case .diamond: Color(red: 0.40, green: 0.85, blue: 1.0)
        case .champion: Color(red: 1.0, green: 0.30, blue: 0.30)
        }
    }

    /// Promote to next league. Returns self if already champion.
    var promoted: League {
        switch self {
        case .bronze: .silver
        case .silver: .gold
        case .gold: .diamond
        case .diamond: .champion
        case .champion: .champion
        }
    }

    /// Demote to previous league. Returns self if already bronze.
    var demoted: League {
        switch self {
        case .bronze: .bronze
        case .silver: .bronze
        case .gold: .silver
        case .diamond: .gold
        case .champion: .diamond
        }
    }
}

// MARK: - DailyXPGoal

enum DailyXPGoal: Int, Codable, CaseIterable {
    case casual = 50
    case regular = 100
    case serious = 200

    var label: String {
        switch self {
        case .casual: "Casual"
        case .regular: "Regular"
        case .serious: "Serious"
        }
    }
}

// MARK: - AchievementRarity

enum AchievementRarity: String, Codable, CaseIterable {
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
