//
// AchievementLibrary.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - Achievement Library

// Pre-defined achievements that get loaded into SwiftData on first launch.
// 25 achievements across all categories, inspired by Duolingo/Strava/Habitica.

@MainActor
struct AchievementLibrary {
    static func loadIfNeeded(context: ModelContext) throws {
        let descriptor = FetchDescriptor<Achievement>()
        let count = try context.fetchCount(descriptor)
        guard count == 0 else {
            return
        }

        for def in allAchievements {
            let achievement = Achievement(
                badgeID: def.badgeID,
                name: def.name,
                description: def.description,
                category: def.category,
                rarity: def.rarity,
                xpReward: def.xpReward,
                isHidden: def.isHidden,
                progressValue: 0,
                targetValue: def.targetValue
            )
            context.insert(achievement)
        }
        try context.save()
    }

    // MARK: - Achievement Definitions

    struct AchievementDef {
        let badgeID: String
        let name: String
        let description: String
        let category: AchievementCategory
        let rarity: AchievementRarity
        let xpReward: Int
        let targetValue: Int
        let isHidden: Bool

        init(
            badgeID: String,
            name: String,
            description: String,
            category: AchievementCategory,
            rarity: AchievementRarity,
            xpReward: Int,
            targetValue: Int,
            isHidden: Bool = false
        ) {
            self.badgeID = badgeID
            self.name = name
            self.description = description
            self.category = category
            self.rarity = rarity
            self.xpReward = xpReward
            self.targetValue = targetValue
            self.isHidden = isHidden
        }
    }

    static let allAchievements: [AchievementDef] = [
        // MARK: Training (7)

        AchievementDef(
            badgeID: "iron_novice",
            name: "Iron Novice",
            description: "Complete 10 workouts",
            category: .training,
            rarity: .common,
            xpReward: 50,
            targetValue: 10
        ),
        AchievementDef(
            badgeID: "century_club",
            name: "Century Club",
            description: "Log 100 workouts",
            category: .training,
            rarity: .rare,
            xpReward: 200,
            targetValue: 100
        ),
        AchievementDef(
            badgeID: "beast_mode",
            name: "Beast Mode",
            description: "Complete a workout with strain > 18",
            category: .training,
            rarity: .epic,
            xpReward: 300,
            targetValue: 1
        ),
        AchievementDef(
            badgeID: "iron_warrior",
            name: "Iron Warrior",
            description: "Complete 500 workouts",
            category: .training,
            rarity: .legendary,
            xpReward: 1000,
            targetValue: 500
        ),
        AchievementDef(
            badgeID: "volume_king",
            name: "Volume King",
            description: "Lift 100,000 kg total volume",
            category: .training,
            rarity: .epic,
            xpReward: 500,
            targetValue: 100_000
        ),
        AchievementDef(
            badgeID: "dawn_warrior",
            name: "Dawn Warrior",
            description: "Complete 10 workouts before 8am",
            category: .training,
            rarity: .uncommon,
            xpReward: 100,
            targetValue: 10
        ),
        AchievementDef(
            badgeID: "pr_machine",
            name: "PR Machine",
            description: "Set 20 personal records",
            category: .training,
            rarity: .rare,
            xpReward: 250,
            targetValue: 20
        ),

        // MARK: Study (4)

        AchievementDef(
            badgeID: "knowledge_seeker",
            name: "Knowledge Seeker",
            description: "Study for 50 hours total",
            category: .study,
            rarity: .rare,
            xpReward: 200,
            targetValue: 3000 // 50 hours in minutes
        ),
        AchievementDef(
            badgeID: "pomodoro_master",
            name: "Pomodoro Master",
            description: "Complete 100 pomodoro sessions",
            category: .study,
            rarity: .uncommon,
            xpReward: 150,
            targetValue: 100
        ),
        AchievementDef(
            badgeID: "scholar",
            name: "Scholar",
            description: "Study for 200 hours total",
            category: .study,
            rarity: .epic,
            xpReward: 500,
            targetValue: 12000 // 200 hours in minutes
        ),
        AchievementDef(
            badgeID: "deep_focus",
            name: "Deep Focus",
            description: "Complete 4 pomodoros in a single session",
            category: .study,
            rarity: .uncommon,
            xpReward: 75,
            targetValue: 1
        ),

        // MARK: Nutrition (3)

        AchievementDef(
            badgeID: "clean_eater",
            name: "Clean Eater",
            description: "Log meals for 7 consecutive days",
            category: .nutrition,
            rarity: .common,
            xpReward: 50,
            targetValue: 7
        ),
        AchievementDef(
            badgeID: "meal_prep_king",
            name: "Meal Prep King",
            description: "Log all meals for 30 consecutive days",
            category: .nutrition,
            rarity: .rare,
            xpReward: 200,
            targetValue: 30
        ),
        AchievementDef(
            badgeID: "macro_wizard",
            name: "Macro Wizard",
            description: "Hit macros within 5% for 7 consecutive days",
            category: .nutrition,
            rarity: .epic,
            xpReward: 300,
            targetValue: 7
        ),

        // MARK: Recovery (3)

        AchievementDef(
            badgeID: "sleep_champion",
            name: "Sleep Champion",
            description: "Get 8+ hours of sleep for 5 consecutive nights",
            category: .recovery,
            rarity: .uncommon,
            xpReward: 100,
            targetValue: 5
        ),
        AchievementDef(
            badgeID: "recovery_master",
            name: "Recovery Master",
            description: "Maintain green recovery for 7 consecutive days",
            category: .recovery,
            rarity: .rare,
            xpReward: 200,
            targetValue: 7
        ),
        AchievementDef(
            badgeID: "zen_mode",
            name: "Zen Mode",
            description: "Achieve 14 days of green recovery",
            category: .recovery,
            rarity: .epic,
            xpReward: 400,
            targetValue: 14
        ),

        // MARK: Consistency (6)

        AchievementDef(
            badgeID: "first_steps",
            name: "First Steps",
            description: "Complete your first day in Tempo",
            category: .consistency,
            rarity: .common,
            xpReward: 25,
            targetValue: 1
        ),
        AchievementDef(
            badgeID: "the_grind",
            name: "The Grind",
            description: "Maintain a 30-day streak",
            category: .consistency,
            rarity: .rare,
            xpReward: 300,
            targetValue: 30
        ),
        AchievementDef(
            badgeID: "diamond_hands",
            name: "Diamond Hands",
            description: "Maintain a 100-day streak",
            category: .consistency,
            rarity: .legendary,
            xpReward: 1500,
            targetValue: 100
        ),
        AchievementDef(
            badgeID: "perfect_week",
            name: "Perfect Week",
            description: "All non-negotiables completed for 7 days straight",
            category: .consistency,
            rarity: .rare,
            xpReward: 200,
            targetValue: 7
        ),
        AchievementDef(
            badgeID: "no_days_off",
            name: "No Days Off",
            description: "Maintain a 14-day streak",
            category: .consistency,
            rarity: .uncommon,
            xpReward: 100,
            targetValue: 14
        ),
        AchievementDef(
            badgeID: "perfect_month",
            name: "Perfect Month",
            description: "All non-negotiables completed for 30 consecutive days",
            category: .consistency,
            rarity: .epic,
            xpReward: 500,
            targetValue: 30
        ),

        // MARK: Milestone (2)

        AchievementDef(
            badgeID: "level_10",
            name: "Rising Star",
            description: "Reach Level 10: Warrior",
            category: .milestone,
            rarity: .uncommon,
            xpReward: 100,
            targetValue: 10
        ),
        AchievementDef(
            badgeID: "level_25",
            name: "Elite Status",
            description: "Reach Level 25: General",
            category: .milestone,
            rarity: .legendary,
            xpReward: 1000,
            targetValue: 25
        ),

        // MARK: Hidden (2)

        AchievementDef(
            badgeID: "night_owl",
            name: "Night Owl",
            description: "Complete a workout after midnight",
            category: .hidden,
            rarity: .uncommon,
            xpReward: 75,
            targetValue: 1,
            isHidden: true
        ),
        AchievementDef(
            badgeID: "comeback_kid",
            name: "Comeback Kid",
            description: "Restart a streak after losing one of 7+ days",
            category: .hidden,
            rarity: .rare,
            xpReward: 150,
            targetValue: 1,
            isHidden: true
        ),
    ]
}
