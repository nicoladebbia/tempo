import Vapor
import Fluent

// MARK: - Achievement Controller
// Per BACKEND_API.md Section 10.8 — Achievement endpoints.

struct AchievementController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get(use: earned)
        routes.get("available", use: available)
        routes.post("check", use: check)
        routes.post(":achievementID", "pin", use: pin)
        routes.delete(":achievementID", "pin", use: unpin)
    }

    // MARK: - GET /v1/achievements
    // Per BACKEND_API.md Section 10.8 — Earned achievements for authenticated user.

    @Sendable
    func earned(req: Request) async throws -> Envelope<[UserAchievementDTO]> {
        let userID = try req.auth.requireUserID()
        let pagination = try req.query.decode(PaginationQuery.self)
        let limit = min(pagination.limit ?? 25, 100)
        let categoryFilter = try? req.query.get(String.self, at: "category")

        let query = UserAchievement.query(on: req.db)
            .filter(\.$userID == userID)
            .sort(\.$earnedAt, .descending)
            .limit(limit)

        let userAchievements = try await query.all()

        // Fetch definitions for earned achievements
        let achievementIDs = userAchievements.map { $0.achievementID }
        var definitions = try await AchievementDefinition.query(on: req.db)
            .filter(\.$id ~~ achievementIDs)
            .all()

        if let category = categoryFilter {
            definitions = definitions.filter { $0.category == category }
        }

        let defMap = Dictionary(uniqueKeysWithValues: definitions.compactMap { d in
            d.id.map { ($0, d) }
        })

        let dtos = userAchievements.compactMap { ua -> UserAchievementDTO? in
            guard let def = defMap[ua.achievementID] else { return nil }
            if let category = categoryFilter, def.category != category { return nil }
            return UserAchievementDTO(
                achievementID: ua.achievementID,
                name: def.name,
                description: def.description,
                category: def.category,
                tier: def.tier,
                xpReward: def.xpReward,
                iconName: def.iconName,
                flavorText: def.flavorText,
                earnedAt: ua.earnedAt,
                pinned: ua.pinned
            )
        }

        return Envelope(data: dtos, requestID: req.requestID)
    }

    // MARK: - GET /v1/achievements/available
    // Per BACKEND_API.md Section 10.8 — Full catalog of all achievement definitions.

    @Sendable
    func available(req: Request) async throws -> Envelope<[AchievementDefinitionDTO]> {
        let userID = try req.auth.requireUserID()

        let definitions = try await AchievementDefinition.query(on: req.db)
            .sort(\.$category)
            .sort(\.$tier)
            .all()

        // Get user's earned achievement IDs
        let earnedIDs = try await UserAchievement.query(on: req.db)
            .filter(\.$userID == userID)
            .all()
            .map { $0.achievementID }

        let earnedSet = Set(earnedIDs)

        let dtos = definitions.compactMap { def -> AchievementDefinitionDTO? in
            // Don't show hidden achievements that haven't been earned
            if def.hidden, !earnedSet.contains(def.id ?? "") {
                return nil
            }

            return AchievementDefinitionDTO(
                id: def.id ?? "",
                name: def.name,
                description: def.description,
                category: def.category,
                tier: def.tier,
                xpReward: def.xpReward,
                criteriaType: def.criteriaType,
                criteriaThreshold: def.criteriaThreshold,
                iconName: def.iconName,
                flavorText: def.flavorText,
                earned: earnedSet.contains(def.id ?? "")
            )
        }

        return Envelope(data: dtos, requestID: req.requestID)
    }

    // MARK: - POST /v1/achievements/check
    // Per BACKEND_API.md Section 10.8 — Trigger achievement evaluation.

    @Sendable
    func check(req: Request) async throws -> Envelope<AchievementCheckResultDTO> {
        let userID = try req.auth.requireUserID()

        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found.")
        }

        // Get all unearned achievements
        let earnedIDs = try await UserAchievement.query(on: req.db)
            .filter(\.$userID == userID)
            .all()
            .map { $0.achievementID }

        let earnedSet = Set(earnedIDs)
        let allDefs = try await AchievementDefinition.query(on: req.db).all()
        let unearnedDefs = allDefs.filter { !earnedSet.contains($0.id ?? "") }

        // Check each unearned achievement against user data
        var newlyEarned: [AchievementEarnedDTO] = []

        for def in unearnedDefs {
            let met = try await checkCriteria(
                def: def,
                userID: userID,
                user: user,
                on: req.db
            )

            if met {
                let ua = UserAchievement(userID: userID, achievementID: def.id ?? "")
                try await ua.save(on: req.db)

                newlyEarned.append(AchievementEarnedDTO(
                    achievementID: def.id ?? "",
                    name: def.name,
                    tier: def.tier,
                    xpReward: def.xpReward
                ))

                // Award XP for the achievement
                let xpEvent = XPEvent(
                    userID: userID,
                    source: "system",
                    baseXP: def.xpReward,
                    metadata: ["type": "achievement_unlocked", "achievement_id": def.id ?? ""]
                )
                try await xpEvent.save(on: req.db)

                user.xpTotal += xpEvent.multipliedXP
                user.level = User.levelForXP(user.xpTotal)
            }
        }

        if !newlyEarned.isEmpty {
            try await user.save(on: req.db)
        }

        return Envelope(
            data: AchievementCheckResultDTO(
                checked: unearnedDefs.count,
                newlyEarned: newlyEarned
            ),
            requestID: req.requestID
        )
    }

    // MARK: - POST /v1/achievements/:id/pin

    @Sendable
    func pin(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        guard let achievementID = req.parameters.get("achievementID") else {
            throw Abort(.badRequest, reason: "Achievement ID required.")
        }

        guard let ua = try await UserAchievement.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$achievementID == achievementID)
            .first() else {
            throw Abort(.notFound, reason: "Achievement not earned.")
        }

        ua.pinned = true
        try await ua.save(on: req.db)

        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - DELETE /v1/achievements/:id/pin

    @Sendable
    func unpin(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        guard let achievementID = req.parameters.get("achievementID") else {
            throw Abort(.badRequest, reason: "Achievement ID required.")
        }

        guard let ua = try await UserAchievement.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$achievementID == achievementID)
            .first() else {
            throw Abort(.notFound, reason: "Achievement not earned.")
        }

        ua.pinned = false
        try await ua.save(on: req.db)

        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - Criteria Checking

    private func checkCriteria(
        def: AchievementDefinition,
        userID: String,
        user: User,
        on db: Database
    ) async throws -> Bool {
        switch def.criteriaType {
        // Workout count achievements
        case "workout_count":
            let count = try await XPEvent.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$source == "whoop")
                .count()
            return count >= def.criteriaThreshold

        // Study hours achievements
        case "study_hours":
            let events = try await XPEvent.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$source == "manual")
                .all()
            // Approximate: each study event ~40 XP = ~45 min
            let hours = events.count // Simplified count
            return hours >= def.criteriaThreshold

        // Streak achievements
        case "streak_days":
            return user.streakDays >= def.criteriaThreshold

        // Level achievements
        case "level":
            return user.level >= def.criteriaThreshold

        // Total XP achievements
        case "total_xp":
            return user.xpTotal >= def.criteriaThreshold

        // Friend count achievements
        case "friend_count":
            let count = try await Friendship.query(on: db)
                .group(.or) { group in
                    group.filter(\.$userAID == userID)
                    group.filter(\.$userBID == userID)
                }
                .count()
            return count >= def.criteriaThreshold

        // Challenge wins
        case "challenge_wins":
            let count = try await ChallengeMember.query(on: db)
                .filter(\.$userID == userID)
                .filter(\.$status == "completed")
                .filter(\.$rank == 1)
                .count()
            return count >= def.criteriaThreshold

        // Perfect days
        case "perfect_days":
            // Simplified: count days where all core XP types were earned
            return false // Full implementation in Phase 15 with AI engine

        // Meals logged (native MealLog source)
        case "meals_logged":
            let count = try await XPEvent.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$source == "meal")
                .count()
            return count >= def.criteriaThreshold

        // Green recovery days
        case "green_recovery_days":
            // Would check Whoop recovery data; simplified here
            return false

        default:
            return false
        }
    }
}

// MARK: - DTOs

struct UserAchievementDTO: Content {
    let achievementID: String
    let name: String
    let description: String
    let category: String
    let tier: String
    let xpReward: Int
    let iconName: String?
    let flavorText: String?
    let earnedAt: Date
    let pinned: Bool

    enum CodingKeys: String, CodingKey {
        case name, description, category, tier, pinned
        case achievementID = "achievement_id"
        case xpReward = "xp_reward"
        case iconName = "icon_name"
        case flavorText = "flavor_text"
        case earnedAt = "earned_at"
    }
}

struct AchievementDefinitionDTO: Content {
    let id: String
    let name: String
    let description: String
    let category: String
    let tier: String
    let xpReward: Int
    let criteriaType: String
    let criteriaThreshold: Int
    let iconName: String?
    let flavorText: String?
    let earned: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, tier, earned
        case xpReward = "xp_reward"
        case criteriaType = "criteria_type"
        case criteriaThreshold = "criteria_threshold"
        case iconName = "icon_name"
        case flavorText = "flavor_text"
    }
}

struct AchievementCheckResultDTO: Content {
    let checked: Int
    let newlyEarned: [AchievementEarnedDTO]

    enum CodingKeys: String, CodingKey {
        case checked
        case newlyEarned = "newly_earned"
    }
}

struct AchievementEarnedDTO: Content {
    let achievementID: String
    let name: String
    let tier: String
    let xpReward: Int

    enum CodingKeys: String, CodingKey {
        case name, tier
        case achievementID = "achievement_id"
        case xpReward = "xp_reward"
    }
}
