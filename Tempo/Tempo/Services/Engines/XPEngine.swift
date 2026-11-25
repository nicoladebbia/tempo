//
// XPEngine.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - XPEngine

// Per MODULE_ARENA.md — XP System. The ONE place the XP amounts live: `dayAwards`
// says what a day of real activity is worth, and the Arena's ledger (ArenaXPLedger)
// is the only thing that writes it down. There are no penalties, no sleep or steps
// bonus and no streak bonus; the streak earns badges, not XP.

final class XPEngine: XPEngineProtocol, @unchecked Sendable {
    // MARK: - XP Values

    // Workout XP
    private let xpWorkoutBase = 50
    private let xpPerExercise = 10
    private let xpFirstWorkoutOfDay = 10
    private let xpEarlyBirdWorkout = 25 // before 8am

    // Meal XP
    private let xpMealEach = 5
    private let xpAllMeals = 40

    // Study XP
    private let xpPerPomodoro = 25
    private let xpFirstStudyOfDay = 10
    private let xpEarlyBirdStudy = 25 // before 8am

    /// Non-negotiables
    private let xpAllNonNeg = 100 // bumped: all non-negotiables done

    // MARK: - Level Calculation (using LevelSystem)

    func currentLevel(totalXP: Int) -> Int {
        LevelSystem.level(forXP: totalXP)
    }

    func xpToNextLevel(totalXP: Int) -> Int {
        LevelSystem.xpForNextLevel(currentXP: totalXP)
    }

    /// Progress toward next level as 0-1 fraction.
    func levelProgress(totalXP: Int) -> Double {
        let current = currentLevel(totalXP: totalXP)
        let currentLevelXP = LevelSystem.xpRequired(for: current)
        let nextLevel = current + 1
        let nextLevelXP = nextLevel <= LevelSystem.definitions.count
            ? LevelSystem.xpRequired(for: nextLevel)
            : currentLevelXP + 10000
        let range = nextLevelXP - currentLevelXP
        guard range > 0 else {
            return 0
        }
        return Double(totalXP - currentLevelXP) / Double(range)
    }

    func levelName(for level: Int) -> String {
        LevelSystem.definition(for: level).name
    }

    func xpForLevel(_ level: Int) -> Int {
        LevelSystem.xpRequired(for: level)
    }

    // MARK: - XP Earning Categories

    /// Exactly what `dayAwards(for:)` pays, so the "How XP works" sheet never
    /// promises XP the app does not give.
    static var xpEarningCategories: [XPEarningCategory] {
        [
            XPEarningCategory(
                emoji: "🏋️", name: "Workout",
                description: "Finish a workout",
                xpRange: "50 + 10 per exercise"
            ),
            XPEarningCategory(
                emoji: "🌅", name: "Early bird workout",
                description: "Start a workout before 8am",
                xpRange: "+25"
            ),
            XPEarningCategory(
                emoji: "📖", name: "Study",
                description: "Every 25 minutes of focus time",
                xpRange: "25 per 25 min, +10 first of the day"
            ),
            XPEarningCategory(
                emoji: "🌅", name: "Early bird study",
                description: "Start studying before 8am",
                xpRange: "+25"
            ),
            XPEarningCategory(
                emoji: "🍴", name: "Meals",
                description: "Log breakfast, lunch, dinner and snacks",
                xpRange: "5 per meal, +40 for all three main meals"
            ),
            XPEarningCategory(
                emoji: "✓", name: "Tasks",
                description: "Finish every daily task",
                xpRange: "+100"
            ),
            XPEarningCategory(
                emoji: "🏅", name: "Achievements",
                description: "Unlock an achievement",
                xpRange: "Set by its rarity"
            ),
        ]
    }
}

// MARK: - Day awards

extension XPEngine {
    /// The XP one day of real activity is worth. No penalties: a day with
    /// nothing in it is worth nothing, never less than nothing.
    func dayAwards(for day: XPDayActivity) -> [XPAward] {
        var awards: [XPAward] = []

        if day.workouts > 0 {
            var amount = xpWorkoutBase * day.workouts
                + xpPerExercise * max(0, day.exercisesPerformed)
                + xpFirstWorkoutOfDay
            if let hour = day.earliestWorkoutHour, hour < 8 {
                amount += xpEarlyBirdWorkout
            }
            awards.append(XPAward(
                source: .workout, amount: amount,
                reason: day.workouts == 1 ? "Finished a workout" : "Finished \(day.workouts) workouts"
            ))
        }

        if day.mealSlotsLogged > 0 {
            var amount = xpMealEach * day.mealSlotsLogged
            if day.mainMealsAllLogged {
                amount += xpAllMeals
            }
            awards.append(XPAward(
                source: .meal, amount: amount,
                reason: day.mainMealsAllLogged ? "Every main meal logged" : "Logged meals"
            ))
        }

        let pomodoros = day.studyMinutes / 25
        if pomodoros > 0 {
            var amount = xpPerPomodoro * pomodoros + xpFirstStudyOfDay
            if let hour = day.earliestStudyHour, hour < 8 {
                amount += xpEarlyBirdStudy
            }
            awards.append(XPAward(source: .study, amount: amount, reason: "\(day.studyMinutes) minutes of focus"))
        }

        if day.allNonNegotiablesDone {
            awards.append(XPAward(source: .nonNegotiable, amount: xpAllNonNeg, reason: "Every daily task done"))
        }
        return awards
    }
}
