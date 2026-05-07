//
// XPEngineProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - XPEngineProtocol

protocol XPEngineProtocol: Sendable {
    func calculateXP(
        from snapshot: DailySnapshot,
        accountability: DailyAccountability
    ) -> [XPEvent]

    func currentLevel(totalXP: Int) -> Int

    func xpToNextLevel(totalXP: Int) -> Int

    func streakMilestoneXP(streakCount: Int) -> XPEvent?

    func levelName(for level: Int) -> String

    func xpForLevel(_ level: Int) -> Int

    /// All XP earning categories with descriptions for the detail sheet.
    static var xpEarningCategories: [XPEarningCategory] { get }
}

// MARK: - XPEarningCategory

struct XPEarningCategory: Identifiable {
    let id = UUID()
    let emoji: String
    let name: String
    let description: String
    let xpRange: String
}

// MARK: - LevelDefinition

struct LevelDefinition {
    let level: Int
    let name: String
    let xpRequired: Int
}

// MARK: - LevelSystem

enum LevelSystem {
    static let definitions: [LevelDefinition] = [
        LevelDefinition(level: 1, name: "Recruit", xpRequired: 0),
        LevelDefinition(level: 2, name: "Recruit", xpRequired: 100),
        LevelDefinition(level: 3, name: "Recruit", xpRequired: 250),
        LevelDefinition(level: 4, name: "Recruit", xpRequired: 400),
        LevelDefinition(level: 5, name: "Soldier", xpRequired: 500),
        LevelDefinition(level: 6, name: "Soldier", xpRequired: 700),
        LevelDefinition(level: 7, name: "Soldier", xpRequired: 950),
        LevelDefinition(level: 8, name: "Soldier", xpRequired: 1200),
        LevelDefinition(level: 9, name: "Soldier", xpRequired: 1550),
        LevelDefinition(level: 10, name: "Warrior", xpRequired: 2000),
        LevelDefinition(level: 11, name: "Warrior", xpRequired: 2500),
        LevelDefinition(level: 12, name: "Warrior", xpRequired: 3100),
        LevelDefinition(level: 13, name: "Warrior", xpRequired: 3800),
        LevelDefinition(level: 14, name: "Warrior", xpRequired: 4500),
        LevelDefinition(level: 15, name: "Captain", xpRequired: 5000),
        LevelDefinition(level: 16, name: "Captain", xpRequired: 6000),
        LevelDefinition(level: 17, name: "Captain", xpRequired: 7200),
        LevelDefinition(level: 18, name: "Captain", xpRequired: 8500),
        LevelDefinition(level: 19, name: "Captain", xpRequired: 9500),
        LevelDefinition(level: 20, name: "Commander", xpRequired: 10000),
        LevelDefinition(level: 21, name: "Commander", xpRequired: 12000),
        LevelDefinition(level: 22, name: "Commander", xpRequired: 14000),
        LevelDefinition(level: 23, name: "Commander", xpRequired: 16000),
        LevelDefinition(level: 24, name: "Commander", xpRequired: 18000),
        LevelDefinition(level: 25, name: "General", xpRequired: 20000),
        LevelDefinition(level: 26, name: "General", xpRequired: 25000),
        LevelDefinition(level: 27, name: "General", xpRequired: 30000),
        LevelDefinition(level: 28, name: "General", xpRequired: 37000),
        LevelDefinition(level: 29, name: "General", xpRequired: 44000),
        LevelDefinition(level: 30, name: "Legend", xpRequired: 50000),
        LevelDefinition(level: 31, name: "Legend", xpRequired: 60000),
        LevelDefinition(level: 32, name: "Legend", xpRequired: 72000),
        LevelDefinition(level: 33, name: "Legend", xpRequired: 85000),
        LevelDefinition(level: 34, name: "Legend", xpRequired: 100_000),
        LevelDefinition(level: 35, name: "Mythic", xpRequired: 120_000),
    ]

    static func definition(for level: Int) -> LevelDefinition {
        let clamped = max(1, min(level, definitions.count))
        return definitions[clamped - 1]
    }

    static func level(forXP xp: Int) -> Int {
        var result = 1
        for def in definitions {
            if xp >= def.xpRequired {
                result = def.level
            } else {
                break
            }
        }
        return result
    }

    static func xpForNextLevel(currentXP: Int) -> Int {
        let currentLevel = level(forXP: currentXP)
        if currentLevel >= definitions.count {
            return 0
        }
        let nextDef = definitions[currentLevel] // index = currentLevel because array is 0-based
        return max(0, nextDef.xpRequired - currentXP)
    }

    static func xpRequired(for level: Int) -> Int {
        let clamped = max(1, min(level, definitions.count))
        return definitions[clamped - 1].xpRequired
    }
}
