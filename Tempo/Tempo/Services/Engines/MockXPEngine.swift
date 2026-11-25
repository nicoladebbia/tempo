//
// MockXPEngine.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

final class MockXPEngine: XPEngineProtocol, @unchecked Sendable {
    func currentLevel(totalXP: Int) -> Int {
        LevelSystem.level(forXP: totalXP)
    }

    func xpToNextLevel(totalXP: Int) -> Int {
        LevelSystem.xpForNextLevel(currentXP: totalXP)
    }

    func levelName(for level: Int) -> String {
        LevelSystem.definition(for: level).name
    }

    func xpForLevel(_ level: Int) -> Int {
        LevelSystem.xpRequired(for: level)
    }

    func dayAwards(for activity: XPDayActivity) -> [XPAward] {
        XPEngine().dayAwards(for: activity)
    }

    static var xpEarningCategories: [XPEarningCategory] {
        XPEngine.xpEarningCategories
    }
}
