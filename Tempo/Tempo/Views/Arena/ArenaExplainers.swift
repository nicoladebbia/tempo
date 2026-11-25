//
// ArenaExplainers.swift
// Tempo
//
// What each number in the Arena means, how it is worked out and what to do about
// it. The "how" follows the code: XP amounts are `XPEngine.dayAwards`, levels are
// `LevelSystem.definitions`, the rows are kept by `ArenaXPLedger`, challenge dates
// and the bar are `ArenaChallengeDTO`. The "How XP works" sheet on the Arena home
// lists the amounts, so these texts point at it instead of repeating the table.
// Change one of those and change its text.
//

import SwiftUI

extension Explainer {
    // MARK: Level and XP

    static let arenaLevel = Explainer(
        id: "arena-level",
        title: "Level",
        what: "Your level, and how far you are from the next one. The ring fills as your total XP gets closer to the XP the next level needs.",
        how: """
        Your level comes from your total XP: level 2 needs 100, level 5 needs 500, level 10 needs 2,000 and level 20 needs 10,000. \
        The title changes at levels 5, 10, 15, 20, 25 and 30. XP is worked out from what you really did: workouts, meals, \
        focus time and finishing your daily tasks. Delete a workout or a study session and its XP goes with it.
        """,
        action: "Finish every daily task today: it is the biggest single award, 100 XP.",
        systemImage: "star.fill"
    )

    static let arenaDailyGoal = Explainer(
        id: "arena-daily-goal",
        title: "Today's XP",
        what: "The XP you have earned today against your daily goal. The bar stops at the goal and the number keeps counting.",
        how: """
        Tempo adds up the XP from today's workouts, meals, focus time and daily tasks, counting from midnight. \
        Your daily goal is 100 XP unless it was set to 50 or 200. The "How XP works" row under it lists what each action pays.
        """,
        action: "Finish a 25 minute focus session: it pays 25 XP, plus 10 for the first one of the day.",
        systemImage: "bolt.fill"
    )

    static let arenaStreak = Explainer(
        id: "arena-streak",
        title: "Streak",
        what: "How many days in a row you have finished your whole list of daily tasks. It is the same streak as on the Streak page.",
        how: """
        A day adds one when every non-negotiable is done or skipped. A rest-day override keeps the streak where it is. \
        A day left unfinished uses one streak freeze if you have one, and breaks the streak if you do not. \
        The streak earns badges and shareable cards, not XP.
        """,
        action: "Finish today's daily tasks before midnight.",
        systemImage: "flame.fill"
    )

    // MARK: Leaderboard

    static let arenaRank = Explainer(
        id: "arena-rank",
        title: "Your rank",
        what: "Your place among you and your friends this week. #1 means you have the most XP.",
        how: """
        The server ranks everyone by the XP earned this week, Monday to Sunday. The numbers are the totals each person's own phone \
        sent, and only friends are on the board. It starts again from zero on Monday.
        """,
        action: "Look at the XP gap to the next person and earn it today with one workout or two focus sessions.",
        systemImage: "trophy.fill"
    )

    static let friendWeeklyXP = Explainer(
        id: "arena-friend-xp",
        title: "A friend's week",
        what: "A friend's level and the XP they have earned this week.",
        how: """
        Friends only share their name, their level and this week's XP: nothing else leaves their phone. \
        The week runs Monday to Sunday and starts again from zero on Monday.
        """,
        action: "Pick a friend who is slightly ahead of you and try to pass them by Sunday.",
        systemImage: "person.2.fill"
    )

    // MARK: Challenges

    static let challengeScore = Explainer(
        id: "arena-challenge-score",
        title: "Challenge score",
        what: "Your score in this challenge, and your place among the people in it. The bar under it shows how much of the time has gone, not your score.",
        how: """
        Your phone counts one number for the challenge's dates only: XP, finished workouts or focus minutes, depending on the challenge. \
        Everyone's phone does the same and the server ranks the totals, so the order is the same on every phone. \
        The bar is the days gone out of the days the challenge runs.
        """,
        action: "Check the days left under the title and do one more thing that counts today.",
        systemImage: "flag.2.crossed.fill"
    )
}
