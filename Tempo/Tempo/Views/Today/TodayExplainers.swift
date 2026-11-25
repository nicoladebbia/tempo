//
// TodayExplainers.swift
// Tempo
//
// What every score, estimate and abbreviation on Today, the week in review,
// the goal and the day timeline means, in three short answers. Each text is
// written from the real calculation in the code it explains: the day score is
// `DashboardViewModel.computeDailyScore`, the streak is the overall `Streak`
// row, the goal line is `GoalEngine`, the week numbers are `WeekReviewBuilder`.
// If one of those changes, change the words here with it.
//
// Where the text depends on the person's own numbers (the lowest part of the
// score, steps still to walk) it is a function; the rest are constants.
//

import Foundation

// MARK: - Day score

extension Explainer {
    /// The four parts of the day score, in the words the breakdown sheet uses.
    enum ScorePart: Equatable {
        case recovery
        case food
        case study
        case movement
    }

    /// The part with the fewest points among those that have data, or nil when
    /// they are all full (or none has data). Points are out of 25.
    static func weakestPart(in breakdown: DashboardViewModel.ScoreBreakdown) -> ScorePart? {
        let parts: [(ScorePart, Double, Bool)] = [
            (.recovery, breakdown.recoveryPoints, breakdown.recoveryAvailable),
            (.food, breakdown.nutritionPoints, breakdown.nutritionAvailable),
            (.study, breakdown.studyPoints, breakdown.studyAvailable),
            (.movement, breakdown.movementPoints, breakdown.movementAvailable),
        ]
        let open = parts.filter { $0.2 && $0.1 < 25 }
        return open.min { $0.1 < $1.1 }?.0
    }

    /// The day score dial. `weakest` makes "what to do" point at the part that
    /// is holding the score down.
    static func dayScore(weakest: ScorePart?) -> Explainer {
        let action: LocalizedStringResource = switch weakest {
        case .recovery: "Recovery is your lowest part. It follows your sleep, so plan an early night."
        case .food: "Food is your lowest part. Log your next meal to lift it."
        case .study: "Study is your lowest part. Start a focus session to lift it."
        case .movement: "Movement is your lowest part. Take a walk or finish today's session to lift it."
        case nil: "Log a meal, study or move and the score fills in."
        }
        return Explainer(
            id: "day-score",
            title: "Day score",
            what: "A number from 0 to 100 for how today is going. 67 and up reads On pace, 34 to 66 Behind, under 34 Off track.",
            how: "It averages four parts: recovery, food, study and movement, each scored 0 to 100. A part with no data is left out and the others share its weight, and it needs at least two parts to show.",
            action: action,
            systemImage: "gauge.with.dots.needle.67percent"
        )
    }

    /// The Recovery row (the Body quadrant).
    static let recoveryPart = Explainer(
        id: "score-recovery",
        title: "Recovery points",
        what: "How recovered your body is today, as your tracker reports it. It is the Body part of your day score.",
        how: "It is your Whoop recovery percentage, worth up to 25 points: 80% gives 20. With no recovery reading from Whoop today, this part is left out.",
        action: "If it reads low, keep today's session lighter and plan an early night.",
        systemImage: "heart.fill"
    )

    /// The Nutrition row (the Fuel quadrant). `kcalLeft` is what is still to eat today.
    static func foodPart(kcalLeft: Int?) -> Explainer {
        let action: LocalizedStringResource = switch kcalLeft {
        case let left? where left > 0: "Log your next meal. You have \(left.formatted()) kcal left to reach your target."
        case nil: "Set up your calorie target in Fuel so this part can fill."
        default: "You have reached your calorie target. Keep logging so tomorrow's targets stay accurate."
        }
        return Explainer(
            id: "score-food",
            title: "Nutrition points",
            what: "How much of today's calorie target you have eaten. It is the Fuel part of your day score.",
            how: "Calories logged divided by your target, up to 100%, worth up to 25 points. Going over the target does not lower it.",
            action: action,
            systemImage: "fork.knife"
        )
    }

    /// The Study row (the Mind quadrant). `minutesLeft` is nil when there is no study target.
    static func studyPart(minutesLeft: Int?) -> Explainer {
        let action: LocalizedStringResource = switch minutesLeft {
        case let left? where left > 0: "Start a focus session. \(left) min gets you to today's target."
        case nil: "Set a study target in your Study task if you want this part to count."
        default: "You have reached today's study target."
        }
        return Explainer(
            id: "score-study",
            title: "Study points",
            what: "How much of today's study target you have done. It is the Mind part of your day score.",
            how: "Minutes studied divided by your daily study target, up to 100%, worth up to 25 points. A target of 0 counts as full.",
            action: action,
            systemImage: "book.fill"
        )
    }

    /// The Movement row (the Move quadrant).
    static func movementPart(stepsTarget: Int, stepsLeft: Int?, sessionDone: Bool) -> Explainer {
        let action: LocalizedStringResource = switch (stepsLeft, sessionDone) {
        case let (left?, false) where left > 0: "Walk \(left.formatted()) more steps or finish today's session to lift it."
        case let (left?, true) where left > 0: "Walk \(left.formatted()) more steps to fill the other half."
        case (nil, true): "Carry your phone so your steps count towards the other half."
        case (_, false): "Finish today's session to fill the other half."
        default: "You have filled both halves today."
        }
        return Explainer(
            id: "score-movement",
            title: "Movement points",
            what: "How much you have moved today. It is the Move part of your day score.",
            how: "Half comes from steps against your \(stepsTarget.formatted()) step target and half from a finished session, up to 25 points together.",
            action: action,
            systemImage: "figure.run"
        )
    }
}

// MARK: - Streak

extension Explainer {
    /// The flame in the Today header. `tasksLeft` is today's open daily tasks.
    static func streak(tasksLeft: Int) -> Explainer {
        let action: LocalizedStringResource = tasksLeft > 0
            ? "You have \(tasksLeft) tasks left today. Finish them all to add a day."
            : "Every task is done today. The day is added when it ends."
        return Explainer(
            id: "streak",
            title: "Day streak",
            what: "How many days in a row you have done every one of your daily tasks.",
            how: "Each day with every task ticked adds one, counted when the day ends. A day with a task missing uses up a streak freeze while you have one left; after that the streak goes back to 0.",
            action: action,
            systemImage: "flame.fill"
        )
    }
}

// MARK: - Week in review

extension Explainer {
    static let weekSessions = Explainer(
        id: "week-sessions",
        title: "Sessions this week",
        what: "How many workouts you finished this week, Monday to Sunday, next to last week.",
        how: "Every session you marked as finished counts as one, however long it was. A session left unfinished does not count.",
        action: "Open Train and book your next session.",
        systemImage: "dumbbell.fill"
    )

    static let weekCalories = Explainer(
        id: "week-calories",
        title: "Calories a day",
        what: "The calories you ate on a typical day this week.",
        how: "The calories of the meals you ate are added up for each day, then averaged over the days that have at least one meal eaten. Days with no meal are left out.",
        action: "Log every meal, even the small ones, so the average is true.",
        systemImage: "fork.knife"
    )

    static let weekRecovery = Explainer(
        id: "week-recovery",
        title: "Average recovery",
        what: "Your recovery score this week, averaged.",
        how: "The mean of your daily recovery scores, over the days that have a reading. Days with no reading are left out.",
        action: "If it fell against last week, plan one lighter day and protect your sleep.",
        systemImage: "heart.fill"
    )

    static let weekTasks = Explainer(
        id: "week-tasks",
        title: "Tasks done",
        what: "The share of your daily tasks you ticked this week.",
        how: "Tasks done divided by tasks set, added up over the days of the week so far.",
        action: "Find the task you miss most and move it to a time you always have free.",
        systemImage: "checklist"
    )
}

// MARK: - Goal

extension Explainer {
    /// "Ahead of your line", "On track", "Behind your line". `pace` is nil when there is no goal to judge.
    static func goalPace(_ pace: GoalProgress.Pace?) -> Explainer {
        let action: LocalizedStringResource = switch pace {
        case .ahead: "You are ahead. Keep the same effort and log your next reading to confirm it."
        case .onTrack: "You are on track. Keep going and log your next reading."
        case .behind: "You are behind. Do your next session or meal on time, or move the date in the goal."
        case .reached: "You got there. Set a new goal to keep going."
        case .noReading,
             nil: "Log a weigh-in, a lift or a run so Tempo has a starting point."
        }
        return Explainer(
            id: "goal-pace",
            title: "Goal pace",
            what: "Whether your latest reading is ahead of, on, or behind the straight line from where you started to your target on your date.",
            how: "Tempo draws that line from your first reading. A reading within a tenth of the whole distance of the line is on track; further along is ahead, further back is behind.",
            action: action,
            systemImage: "target"
        )
    }

    /// The "Now" reading in the goal editor, for the kind of goal being set.
    static func goalReading(_ kind: GoalKind) -> Explainer {
        let how: LocalizedStringResource = switch kind {
        case .bodyWeight: "It is your most recent weigh-in."
        case .liftE1RM: "It is the highest estimated one-rep max in this lift's history. It is an estimate, not a lift you have tested."
        case .runTime: "It is your fastest run at least 95% as long as the distance, scaled to exactly that distance at its average pace."
        }
        return Explainer(
            id: "goal-reading",
            title: "Your reading now",
            what: "Where you stand today on this goal. Your first reading after you set the goal becomes its starting point.",
            how: how,
            action: "Log a new reading when you have one, so the pace stays current.",
            systemImage: "scope"
        )
    }
}

// MARK: - Day timeline

extension Explainer {
    static let dayOrder = Explainer(
        id: "day-order",
        title: "How your day is ordered",
        what: "Your meals, session, study and calendar events for today, in time order. A meal not eaten 90 minutes after its planned time reads Missed.",
        how: "A meal sits at its planned time, or the time you ate it. A session with no set hour sits in the part of the day you said you train: an hour after you wake, 12:00 or 18:00.",
        action: "Tap a row to open it, and log a meal when you eat it so it never reads Missed.",
        systemImage: "list.bullet"
    )

    static let tomorrowWake = Explainer(
        id: "tomorrow-wake",
        title: "Wake time",
        what: "The time tomorrow starts.",
        how: "It is the wake time you set in Settings, under Schedule. Tempo does not measure when you really wake.",
        action: "Set your real wake time in Settings, Schedule, so meals and sessions are placed around it.",
        systemImage: "alarm.fill"
    )
}
