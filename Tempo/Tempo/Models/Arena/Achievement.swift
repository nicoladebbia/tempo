//
// Achievement.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - Achievement

@Model
final class Achievement {
    @Attribute(.unique)
    var id: UUID

    @Attribute(.unique)
    var badgeID: String

    var name: String

    var achievementDescription: String

    var categoryRaw: String

    var rarityRaw: String

    var xpReward: Int

    var earnedAt: Date?

    var isHidden: Bool

    var progressValue: Int

    var targetValue: Int

    // MARK: - Computed

    @Transient
    var category: AchievementCategory {
        get { AchievementCategory(rawValue: categoryRaw) ?? .milestone }
        set { categoryRaw = newValue.rawValue }
    }

    @Transient
    var rarity: AchievementRarity {
        get { AchievementRarity(rawValue: rarityRaw) ?? .common }
        set { rarityRaw = newValue.rawValue }
    }

    @Transient
    var isEarned: Bool {
        earnedAt != nil
    }

    @Transient
    var progressFraction: Double {
        guard targetValue > 0 else {
            return 0
        }
        return min(Double(progressValue) / Double(targetValue), 1.0)
    }

    @Transient
    var effectiveXPReward: Int {
        Int(Double(xpReward) * rarity.xpMultiplier)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        badgeID: String,
        name: String,
        description: String,
        category: AchievementCategory,
        rarity: AchievementRarity,
        xpReward: Int,
        earnedAt: Date? = nil,
        isHidden: Bool = false,
        progressValue: Int = 0,
        targetValue: Int = 0
    ) {
        self.id = id
        self.badgeID = badgeID
        self.name = name
        achievementDescription = description
        categoryRaw = category.rawValue
        rarityRaw = rarity.rawValue
        self.xpReward = xpReward
        self.earnedAt = earnedAt
        self.isHidden = isHidden
        self.progressValue = progressValue
        self.targetValue = targetValue
    }
}

// MARK: - DTO

extension Achievement {
    struct DTO: Codable {
        let id: UUID
        let badge_id: String
        let name: String
        let description: String
        let category: String
        let rarity: String
        let xp_reward: Int
        let earned_at: Date?
        let is_hidden: Bool
        let progress_value: Int
        let target_value: Int
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            badge_id: badgeID,
            name: name,
            description: achievementDescription,
            category: categoryRaw,
            rarity: rarityRaw,
            xp_reward: xpReward,
            earned_at: earnedAt,
            is_hidden: isHidden,
            progress_value: progressValue,
            target_value: targetValue
        )
    }
}
