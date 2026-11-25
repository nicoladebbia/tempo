//
// StudyExplainers.swift
// Tempo
//
// What each number on the Study page, the focus timer, Lockdown and the Streak
// page means, how it is worked out and what to do about it. The "how" follows the
// code: the focus score is `AccountabilityViewModel.computeFocusScore`, the day
// score is `AccountabilityEngine.calculateDailyScore`, the pace line is
// `LockdownPace`, the streak rules are `AccountabilityEngine.updateStreak`.
// Change one of those and change its text.
//

import SwiftUI

extension Explainer {
    // MARK: Study page

    static let studyTarget = Explainer(
        id: "study-target",
        title: "Study target",
        what: "How much of today's study goal you have reached, as a percentage. It stops at 100 on the dial, and the minutes keep counting past it.",
        how: """
        Tempo takes the minutes your focus sessions have added to today and divides them by your daily study target. \
        The target is the one on your Study non-negotiable, 2 hours unless you changed it.
        """,
        action: "Start a focus session now: every 25 minutes is about 20 percent of a 2 hour target.",
        systemImage: "book.fill"
    )

    static let studyStreak = Explainer(
        id: "study-streak",
        title: "Streak",
        what: "How many days in a row you have finished your whole list of non-negotiables. It is your overall streak, not a separate study one.",
        how: """
        A day adds one when every non-negotiable is done or skipped. A rest-day override keeps the streak where it is. \
        A day left unfinished uses one streak freeze if you have one, and breaks the streak if you do not.
        """,
        action: "Finish the Study task today before anything else is left open, so one missed hour cannot cost you the streak.",
        systemImage: "flame.fill"
    )

    static let focusScore = Explainer(
        id: "study-focus-score",
        title: "Focus score",
        what: "How undisturbed a session was, from 0 to 100. Higher means you stayed with the work.",
        how: """
        When you finish a session Tempo scores it from four things: distractions count for 35 percent, how often you paused for 25, \
        how long the pauses were for 20, and how many of the planned pomodoros you finished for 20. \
        A session saved without a review is scored 100 minus 10 for every distraction.
        """,
        action: "Put your phone in another room before you press start: every distraction costs you points.",
        systemImage: "brain.head.profile"
    )

    static let focusScoreLive = Explainer(
        id: "study-focus-score-live",
        title: "Focus score so far",
        what: "Your focus score while the timer is running. It only goes down.",
        how: """
        It starts at 100 and loses 10 for every distraction. A distraction is a tap on Distracted, or each time you leave Tempo \
        while a focus session runs. The score saved with the session also weighs your pauses and finished pomodoros, \
        so it can end up different from this number.
        """,
        action: "Stay in the app until the bell: leaving it counts as a distraction.",
        systemImage: "brain.head.profile"
    )

    static let averageFocus = Explainer(
        id: "study-average-focus",
        title: "Average focus",
        what: "The average focus score of your sessions that have one.",
        how: """
        Tempo averages the score of every session that was scored or had a distraction recorded. \
        Sessions with neither are left out, so a session with nothing recorded does not pull the average to zero.
        """,
        action: "Look at your lowest scored session and ask what interrupted it: remove that one thing next time.",
        systemImage: "brain.head.profile"
    )

    static let bestDay = Explainer(
        id: "study-best-day",
        title: "Best day",
        what: "The single day on which you studied the most.",
        how: "Tempo adds up the minutes of your finished sessions for each day and shows the day with the most. If two days tie, the earlier one wins.",
        action: "Try to beat that total this week: it shows what you can do on a good day.",
        systemImage: "trophy.fill"
    )

    static let studyHeatmap = Explainer(
        id: "study-heatmap",
        title: "Time of day",
        what: "When you study. Each square is one weekday and one hour, and a darker square means more minutes.",
        how: """
        Tempo takes your sessions from the last 30 days and puts each one in the square of the weekday and hour it started. \
        Only sessions that started between 6 in the morning and 10 at night are shown. The darkest square has the most minutes.
        """,
        action: "Book your hardest subject in your darkest hour this week.",
        systemImage: "clock.fill"
    )

    // MARK: Lockdown

    static let lockdownProgress = Explainer(
        id: "lockdown-progress",
        title: "Done",
        what: "How much of today's list of non-negotiables is finished. At 100 percent the day unlocks.",
        how: """
        Tempo divides the tasks that are done or skipped by all of today's tasks. When they are all done you get a day score out of 100: \
        80 points for the tasks, 10 more for finishing everything, and a time bonus of 10 points if you finished before noon \
        or 5 if you finished before 5 in the afternoon.
        """,
        action: "Do the task at the top of the list now: finishing before noon is worth the most.",
        systemImage: "lock.open.fill"
    )

    static let lockdownPace = Explainer(
        id: "lockdown-pace",
        title: "Pace",
        what: "Whether you will finish your list before PS5 time at the speed you are going.",
        how: """
        Tempo treats your day as 11.5 hours that end at PS5 time. It divides the time gone by the tasks you have finished, \
        multiplies that by the tasks left, and compares it with the time you have. It needs one task done and half an hour of the day gone. \
        If the study time you still owe is longer than the time left, it says so first.
        """,
        action: "If it says you are behind, start the longest open task first.",
        systemImage: "speedometer"
    )

    static let habitStreak = Explainer(
        id: "lockdown-habit-streak",
        title: "Task streak",
        what: "How many days in a row you have finished this one task.",
        how: "Study, training and meals each keep their own count. It goes up when you finish that task on a day. It is separate from your overall streak.",
        action: "Open the tasks with a short streak first: they are the easiest to lose.",
        systemImage: "flame.fill"
    )

    // MARK: Streak page

    static let currentStreak = Explainer(
        id: "streak-current",
        title: "Current streak",
        what: "How many days in a row you have finished your whole list. The ring fills toward the next milestone.",
        how: """
        A day adds one when every non-negotiable is done or skipped. A rest-day override keeps the streak where it is. \
        A day left unfinished uses one streak freeze if you have one, and breaks the streak if you do not. The longest streak is your best run.
        """,
        action: "If it says at risk, finish your open tasks before midnight: it shows in the last two hours of the day.",
        systemImage: "flame.fill"
    )

    static let streakFreezes = Explainer(
        id: "streak-freezes",
        title: "Streak freezes",
        what: "Spare lives for your streak. Each one saves a day you did not finish.",
        how: """
        You start with 2. When a day ends unfinished and you have a freeze left, Tempo uses one and the streak stays. \
        Once they are used they are gone: Tempo does not refill them. A rest-day override does not use one.
        """,
        action: "Keep the freezes for real emergencies and do not plan around them.",
        systemImage: "snowflake"
    )

    static let streakMilestones = Explainer(
        id: "streak-milestones",
        title: "Milestones",
        what: "The stops on the way: 3, 5, 7, 14, 21, 30, 50 and 100 days.",
        how: "A stop is reached when your current streak gets to it. The line under a stop says what it gives you, and the ring on the streak shows how far you are from the next one.",
        action: "Look at the next stop and plan the days to it: you only need to finish each day.",
        systemImage: "flag.checkered"
    )

    static let streakHistory = Explainer(
        id: "streak-history",
        title: "365 day history",
        what: "Every day of the last year as one square. A darker square is a better day.",
        how: "The shade is the day score out of 100. A day with no record is empty.",
        action: "Find the empty or pale squares: they show which weekdays you lose, so protect those first.",
        systemImage: "square.grid.3x3.fill"
    )
}
