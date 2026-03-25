import Foundation

// MARK: - XP Engine (Real Implementation)
// Per BUILD_PLAN step 10.7.
// Per MODULE_ARENA.md — XP System.

final class XPEngine: XPEngineProtocol, @unchecked Sendable {

    // MARK: - XP Values
    // Per BUILD_PLAN 10.7:
    //   Workout: +50
    //   Meal: +5 each, +40 all logged
    //   Study target: +40
    //   All non-negotiables: +20 bonus
    //   Sleep score >= 85%: +10
    //   Steps >= 8000: +10
    //   Penalties: skip workout -20, miss study -15, miss meal -10
    //   Streak bonuses: 7-day +25/day, 30-day +50/day

    private let xpWorkout = 50
    private let xpMealEach = 5
    private let xpAllMeals = 40
    private let xpStudyTarget = 40
    private let xpAllNonNeg = 20
    private let xpSleepBonus = 10
    private let xpStepsBonus = 10
    private let xpPenaltySkipWorkout = -20
    private let xpPenaltyMissStudy = -15
    private let xpPenaltyMissMeal = -10
    private let xpStreakWeekly = 25
    private let xpStreakMonthly = 50

    // MARK: - Calculate XP

    func calculateXP(
        from snapshot: DailySnapshot,
        accountability: DailyAccountability
    ) -> [XPEvent] {
        let today = Date()
        var events: [XPEvent] = []

        // Workout XP
        if snapshot.workoutCompleted {
            events.append(XPEvent(
                date: today,
                source: .workout,
                amount: xpWorkout,
                description: "Completed workout"
            ))
        } else {
            // Penalty: skipped workout (only if training was a non-negotiable)
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

        // Meal XP
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

        // Study XP
        if snapshot.studyTarget > 0 && snapshot.studyMinutes >= snapshot.studyTarget {
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

        // All non-negotiables bonus
        if accountability.allComplete {
            events.append(XPEvent(
                date: today,
                source: .nonNegotiable,
                amount: xpAllNonNeg,
                description: "All non-negotiables complete"
            ))
        }

        // Sleep bonus
        if let sleepScore = snapshot.sleepScore, sleepScore >= 0.85 {
            events.append(XPEvent(
                date: today,
                source: .sleep,
                amount: xpSleepBonus,
                description: "Sleep score \(Int(sleepScore * 100))%"
            ))
        }

        // Steps bonus
        if let steps = snapshot.steps, steps >= 8000 {
            events.append(XPEvent(
                date: today,
                source: .steps,
                amount: xpStepsBonus,
                description: "\(steps) steps"
            ))
        }

        // Perfect day bonus (all complete + good sleep + workout + meals)
        if accountability.allComplete
            && snapshot.workoutCompleted
            && mealsLogged >= snapshot.mealsPlanned
            && snapshot.mealsPlanned > 0
            && (snapshot.sleepScore ?? 0) >= 0.80
        {
            events.append(XPEvent(
                date: today,
                source: .perfectDay,
                amount: 50,
                description: "Perfect day"
            ))
        }

        return events
    }

    // MARK: - Streak XP

    /// Calculate streak bonus XP.
    /// Per BUILD_PLAN 10.7: 7-day streak +25/day, 30-day +50/day.
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

    // MARK: - Level Calculation
    // Per BUILD_PLAN 10.7: Level = floor(sqrt(totalXP / 100))

    func currentLevel(totalXP: Int) -> Int {
        guard totalXP > 0 else { return 0 }
        return Int(sqrt(Double(totalXP) / 100.0))
    }

    func xpToNextLevel(totalXP: Int) -> Int {
        let current = currentLevel(totalXP: totalXP)
        let nextLevelXP = (current + 1) * (current + 1) * 100
        return max(0, nextLevelXP - totalXP)
    }

    /// Progress toward next level as 0-1 fraction.
    func levelProgress(totalXP: Int) -> Double {
        let current = currentLevel(totalXP: totalXP)
        let currentLevelXP = current * current * 100
        let nextLevelXP = (current + 1) * (current + 1) * 100
        let range = nextLevelXP - currentLevelXP
        guard range > 0 else { return 0 }
        return Double(totalXP - currentLevelXP) / Double(range)
    }
}
