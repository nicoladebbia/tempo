import Foundation
import SwiftData

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
        isHidden: Bool = false
    ) {
        self.id = id
        self.badgeID = badgeID
        self.name = name
        self.achievementDescription = description
        self.categoryRaw = category.rawValue
        self.rarityRaw = rarity.rawValue
        self.xpReward = xpReward
        self.earnedAt = earnedAt
        self.isHidden = isHidden
    }
}

// MARK: - DTO

extension Achievement {

    struct DTO: Codable, Sendable {
        let id: UUID
        let badge_id: String
        let name: String
        let description: String
        let category: String
        let rarity: String
        let xp_reward: Int
        let earned_at: Date?
        let is_hidden: Bool
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
            is_hidden: isHidden
        )
    }
}
