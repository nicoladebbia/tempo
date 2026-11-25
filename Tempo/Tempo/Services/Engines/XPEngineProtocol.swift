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
        accountability: DailyAccountability,
        floorForcedRest: Bool
    ) -> [XPEvent]

    func currentLevel(totalXP: Int) -> Int

    func xpToNextLevel(totalXP: Int) -> Int

    func streakMilestoneXP(streakCount: Int) -> XPEvent?

    func levelName(for level: Int) -> String

    func xpForLevel(_ level: Int) -> Int

    /// The XP a day of real activity is worth. The ONE place the numbers live:
    /// the Arena's ledger asks, it never invents an amount of its own.
    func dayAwards(for activity: XPDayActivity) -> [XPAward]

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

// MARK: - XPDayActivity

/// What one calendar day actually held, counted from the user's own records.
struct XPDayActivity: Equatable, Sendable {
    /// Workouts finished that day.
    var workouts = 0
    /// Exercises with at least one logged working set, across those workouts.
    var exercisesPerformed = 0
    /// Hour (0-23) the day's earliest workout started, when it is known.
    var earliestWorkoutHour: Int?
    /// Distinct meal slots (breakfast, lunch, ...) with something logged.
    var mealSlotsLogged = 0
    /// Breakfast, lunch and dinner were all logged.
    var mainMealsAllLogged = false
    var studyMinutes = 0
    /// Hour (0-23) the day's earliest study session started, when it is known.
    var earliestStudyHour: Int?
    /// Every daily non-negotiable was done.
    var allNonNegotiablesDone = false

    var isEmpty: Bool {
        workouts == 0 && mealSlotsLogged == 0 && studyMinutes == 0 && !allNonNegotiablesDone
    }
}

// MARK: - XPAward

/// One source's XP for one day, with the sentence that says why.
struct XPAward: Equatable, Sendable {
    let source: XPSource
    let amount: Int
    let reason: String
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

    /// A title that is different for every level: the band's name on its first
    /// level, then "Recruit II", "Recruit III" and so on. `definition(for:).name`
    /// stays the band, for the places that mean the band ("Reach Level 10: Warrior").
    static func displayTitle(for level: Int) -> String {
        let def = definition(for: level)
        let place = definitions.prefix { $0.level < def.level }.count { $0.name == def.name }
        guard place > 0 else {
            return def.name
        }
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
        return "\(def.name) \(numerals[min(place, numerals.count - 1)])"
    }

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
