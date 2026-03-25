import Fluent
import Vapor

// MARK: - Achievement Definition Model
// Per MODULE_ARENA.md Section 21 — Achievement system.
// Per BACKEND_API.md Section 10.8 — Achievement endpoints.

final class AchievementDefinition: Model, Content, @unchecked Sendable {
    static let schema = "achievement_definitions"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "name")
    var name: String

    @Field(key: "description")
    var description: String

    @Field(key: "category")
    var category: String // training, study, nutrition, recovery, streaks, social, steps

    @Field(key: "tier")
    var tier: String // common, rare, epic, legendary, mythic

    @Field(key: "xp_reward")
    var xpReward: Int

    @Field(key: "criteria_type")
    var criteriaType: String // workout_count, study_hours, etc.

    @Field(key: "criteria_threshold")
    var criteriaThreshold: Int

    @OptionalField(key: "icon_name")
    var iconName: String?

    @Field(key: "hidden")
    var hidden: Bool

    @OptionalField(key: "flavor_text")
    var flavorText: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: String,
        name: String,
        description: String,
        category: String,
        tier: String,
        xpReward: Int,
        criteriaType: String,
        criteriaThreshold: Int,
        iconName: String? = nil,
        hidden: Bool = false,
        flavorText: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.tier = tier
        self.xpReward = xpReward
        self.criteriaType = criteriaType
        self.criteriaThreshold = criteriaThreshold
        self.iconName = iconName
        self.hidden = hidden
        self.flavorText = flavorText
    }
}

// MARK: - User Achievement (Earned)

final class UserAchievement: Model, Content, @unchecked Sendable {
    static let schema = "user_achievements"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userID: String

    @Field(key: "achievement_id")
    var achievementID: String

    @Field(key: "earned_at")
    var earnedAt: Date

    @Field(key: "pinned")
    var pinned: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(userID: String, achievementID: String) {
        self.userID = userID
        self.achievementID = achievementID
        self.earnedAt = Date()
        self.pinned = false
    }
}
