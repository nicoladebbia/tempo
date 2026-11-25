//
// XPEngine.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - XP Engine (Real Implementation)

// Per BUILD_PLAN step 10.7.
// Per MODULE_ARENA.md — XP System.
// Enhanced with granular XP awards, streak milestones, per-exercise bonuses,
// pomodoro tracking, early bird bonuses, and perfect day detection.

final class XPEngine: XPEngineProtocol, @unchecked Sendable {
    // MARK: - XP Values (Enhanced)

    // Workout XP
    private let xpWorkoutBase = 50
    private let xpPerExercise = 10
    private let xpFirstWorkoutOfDay = 10
    private let xpEarlyBirdWorkout = 25 // before 8am

    // Meal XP
    private let xpMealEach = 5
    private let xpAllMeals = 40

    // Study XP
    private let xpStudyTarget = 40
    private let xpPerPomodoro = 25
    private let xpFirstStudyOfDay = 10
    private let xpEarlyBirdStudy = 25 // before 8am

    /// Non-negotiables
    private let xpAllNonNeg = 100 // bumped: all non-negotiables done

    // Sleep & Steps
    private let xpSleepBonus = 10
    private let xpStepsBonus = 10

    /// Perfect day (all 5 quadrants green)
    private let xpPerfectDay = 150

    // Penalties
    private let xpPenaltySkipWorkout = -20
    private let xpPenaltyMissStudy = -15
    private let xpPenaltyMissMeal = -10

    // Streak daily bonuses
    private let xpStreakWeekly = 25
    private let xpStreakMonthly = 50

    /// Streak milestones (one-time)
    private let streakMilestones: [(days: Int, xp: Int)] = [
        (7, 200),
        (14, 500),
        (30, 1000),
        (60, 2000),
        (100, 5000),
    ]

    // MARK: - Calculate XP

    /// - Parameter floorForcedRest: true when today's planned workout was
    ///   superseded by the safety floor (a recovery day the BODY demanded, not a
    ///   user flake — INTELLIGENT_TRAINING_SYSTEM §15.2 / WorkoutPlan.skipReason
    ///   == .floorForced). When true, the "missed training" penalty is suppressed:
    ///   the app must never punish the user for OBEYING its own recovery
    ///   prescription. Defaulted false so existing callers are unaffected.
    func calculateXP(
        from snapshot: DailySnapshot,
        accountability: DailyAccountability,
        floorForcedRest: Bool = false
    ) -> [XPEvent] {
        let today = Date()
        let hour = Calendar.current.component(.hour, from: today)
        var events: [XPEvent] = []

        // --- Workout XP ---
        if snapshot.workoutCompleted {
            // Base workout XP
            events.append(XPEvent(
                date: today,
                source: .workout,
                amount: xpWorkoutBase,
                description: "Completed workout"
            ))

            // Per-exercise bonus (use nonNegotiablesCompleted as proxy for exercise count if available)
            let exerciseCount = max(0, snapshot.nonNegotiablesCompleted)
            if exerciseCount > 0 {
                events.append(XPEvent(
                    date: today,
                    source: .workout,
                    amount: exerciseCount * xpPerExercise,
                    description: "\(exerciseCount) exercises completed"
                ))
            }

            // First workout of the day bonus
            events.append(XPEvent(
                date: today,
                source: .workout,
                amount: xpFirstWorkoutOfDay,
                description: "First workout of the day"
            ))

            // Early bird bonus (before 8am)
            if hour < 8 {
                events.append(XPEvent(
                    date: today,
                    source: .workout,
                    amount: xpEarlyBirdWorkout,
                    description: "Early bird workout (before 8am)"
                ))
            }
        } else if !floorForcedRest {
            // Penalty: skipped workout (only if training was a non-negotiable AND
            // the skip was NOT a floor-forced recovery day — §15.2: body-data-wins
            // recovery is compliance, not a miss; never penalize obeying it).
            let hadTraining = accountability.nonNegotiableProgress?.contains {
                $0.nonNegotiable?.type == .train
            } ?? false
            if hadTraining {
                events.append(XPEvent(
                    date: today,
                    source: .penalty,
                    amount: xpPenaltySkipWorkout,
                    description: "Missed training"
                ))
            }
        }

        // --- Meal XP ---
        let mealsLogged = snapshot.mealsLogged
        if mealsLogged > 0 {
            events.append(XPEvent(
                date: today,
                source: .meal,
                amount: mealsLogged * xpMealEach,
                description: "\(mealsLogged) meal\(mealsLogged > 1 ? "s" : "") logged"
            ))
        }
        if mealsLogged >= snapshot.mealsPlanned && snapshot.mealsPlanned > 0 {
            events.append(XPEvent(
                date: today,
                source: .meal,
                amount: xpAllMeals,
                description: "All meals logged"
            ))
        } else if snapshot.mealsPlanned > 0 && mealsLogged < snapshot.mealsPlanned {
            let missed = snapshot.mealsPlanned - mealsLogged
            events.append(XPEvent(
                date: today,
                source: .penalty,
                amount: xpPenaltyMissMeal * missed,
                description: "Missed \(missed) meal\(missed > 1 ? "s" : "")"
            ))
        }

        // --- Study XP ---
        // Per-pomodoro XP (25 min = 1 pomodoro)
        let pomodorosCompleted = snapshot.studyMinutes / 25
        if pomodorosCompleted > 0 {
            events.append(XPEvent(
                date: today,
                source: .study,
                amount: pomodorosCompleted * xpPerPomodoro,
                description: "\(pomodorosCompleted) pomodoro\(pomodorosCompleted > 1 ? "s" : "") completed"
            ))

            // First study of the day
            events.append(XPEvent(
                date: today,
                source: .study,
                amount: xpFirstStudyOfDay,
                description: "First study session"
            ))

            // Early bird study
            if hour < 8 {
                events.append(XPEvent(
                    date: today,
                    source: .study,
                    amount: xpEarlyBirdStudy,
                    description: "Early bird study (before 8am)"
                ))
            }
        } else if snapshot.studyTarget > 0 && snapshot.studyMinutes >= snapshot.studyTarget {
            events.append(XPEvent(
                date: today,
                source: .study,
                amount: xpStudyTarget,
                description: "Study target met (\(snapshot.studyMinutes)m)"
            ))
        } else if snapshot.studyTarget > 0 && snapshot.studyMinutes == 0 {
            events.append(XPEvent(
                date: today,
                source: .penalty,
                amount: xpPenaltyMissStudy,
                description: "No study logged"
            ))
        }

        // --- All non-negotiables bonus (enhanced: 100 XP) ---
        if accountability.allComplete {
            events.append(XPEvent(
                date: today,
                source: .nonNegotiable,
                amount: xpAllNonNeg,
                description: "All non-negotiables complete"
            ))
        }

        // --- Sleep bonus ---
        if let sleepScore = snapshot.sleepScore, sleepScore >= 0.85 {
            events.append(XPEvent(
                date: today,
                source: .sleep,
                amount: xpSleepBonus,
                description: "Sleep score \(Int(sleepScore * 100))%"
            ))
        }

        // --- Steps bonus ---
        if let steps = snapshot.steps, steps >= 8000 {
            events.append(XPEvent(
                date: today,
                source: .steps,
                amount: xpStepsBonus,
                description: "\(steps) steps"
            ))
        }

        // --- Perfect day bonus (all 5 quadrants green: 150 XP) ---
        // Body (recovery/sleep good) + Fuel (meals logged) + Mind (study done) + Move (workout + steps)
        let bodyGreen = (snapshot.sleepScore ?? 0) >= 0.80 && (snapshot.recoveryScore ?? 0) >= 0.60
        let fuelGreen = mealsLogged >= snapshot.mealsPlanned && snapshot.mealsPlanned > 0
        let mindGreen = snapshot.studyTarget > 0 ? snapshot.studyMinutes >= snapshot.studyTarget : true
        let moveGreen = snapshot.workoutCompleted && (snapshot.steps ?? 0) >= 5000
        let tasksGreen = accountability.allComplete

        if bodyGreen, fuelGreen, mindGreen, moveGreen, tasksGreen {
            events.append(XPEvent(
                date: today,
                source: .perfectDay,
                amount: xpPerfectDay,
                description: "Perfect day -- all 5 quadrants green"
            ))
        }

        return events
    }

    // MARK: - Streak XP (daily recurring bonus)

    /// Calculate daily streak bonus XP.
    func streakXP(streakCount: Int) -> XPEvent? {
        if streakCount >= 30 {
            return XPEvent(
                date: Date(),
                source: .streak,
                amount: xpStreakMonthly,
                description: "\(streakCount)-day streak bonus"
            )
        }
        if streakCount >= 7 {
            return XPEvent(
                date: Date(),
                source: .streak,
                amount: xpStreakWeekly,
                description: "\(streakCount)-day streak bonus"
            )
        }
        return nil
    }

    // MARK: - Streak Milestone XP (one-time bonus at specific days)

    func streakMilestoneXP(streakCount: Int) -> XPEvent? {
        guard let milestone = streakMilestones.first(where: { $0.days == streakCount }) else {
            return nil
        }
        return XPEvent(
            date: Date(),
            source: .streak,
            amount: milestone.xp,
            description: "\(streakCount)-day streak milestone!"
        )
    }

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
