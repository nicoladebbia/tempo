//
// MockXPEngine.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

final class MockXPEngine: XPEngineProtocol, @unchecked Sendable {
    func calculateXP(
        from snapshot: DailySnapshot,
        accountability: DailyAccountability,
        floorForcedRest: Bool = false
    ) -> [XPEvent] {
        [
            XPEvent(date: Date(), source: .workout, amount: 50, description: "Completed push workout"),
            XPEvent(date: Date(), source: .workout, amount: 40, description: "4 exercises completed"),
            XPEvent(date: Date(), source: .study, amount: 50, description: "2 pomodoros completed"),
            XPEvent(date: Date(), source: .meal, amount: 55, description: "All meals logged"),
            XPEvent(date: Date(), source: .nonNegotiable, amount: 100, description: "All non-negotiables complete"),
        ]
    }

    func currentLevel(totalXP: Int) -> Int {
        LevelSystem.level(forXP: totalXP)
    }

    func xpToNextLevel(totalXP: Int) -> Int {
        LevelSystem.xpForNextLevel(currentXP: totalXP)
    }

    func streakMilestoneXP(streakCount: Int) -> XPEvent? {
        let milestones: [(Int, Int)] = [(7, 200), (14, 500), (30, 1000), (60, 2000), (100, 5000)]
        guard let m = milestones.first(where: { $0.0 == streakCount }) else {
            return nil
        }
        return XPEvent(date: Date(), source: .streak, amount: m.1, description: "\(streakCount)-day streak milestone!")
    }

    func levelName(for level: Int) -> String {
        LevelSystem.definition(for: level).name
    }

    func xpForLevel(_ level: Int) -> Int {
        LevelSystem.xpRequired(for: level)
    }

    static var xpEarningCategories: [XPEarningCategory] {
        XPEngine.xpEarningCategories
    }
}
