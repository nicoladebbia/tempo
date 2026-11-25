//
// TodayPromptPlanner.swift
// Tempo
//
// Today stays calm: of the cards that ask for attention, at most one is shown
// at a time, chosen here. Everything else waits in a quiet row of links at the
// bottom of the page. Pure: facts and the time in, one answer out.
//

import Foundation

enum TodayPromptPlanner {
    /// A card that asks for the person's attention.
    enum Prompt: Equatable {
        /// The "Get set up" checklist.
        case setup
        /// The week just gone, in four lines.
        case weekReview
        /// Tomorrow's session, first meal and first task.
        case tomorrow
    }

    struct Facts: Equatable {
        var setupVisible = false
        var hasWeekData = false
        var tomorrowHasContent = false
        var leisureMinutes = 19 * 60 + 30
    }

    /// The Monday window ends at this hour.
    static let mondayMorningEnd = 12

    /// The one card to show, or nil when the page has nothing to ask.
    static func prominent(_ facts: Facts, now: Date, calendar: Calendar = .current) -> Prompt? {
        if facts.setupVisible {
            return .setup
        }
        if facts.hasWeekData, isWeekReviewTime(now: now, leisureMinutes: facts.leisureMinutes, calendar: calendar) {
            return .weekReview
        }
        if facts.tomorrowHasContent, DayTimeline.isEvening(now: now, leisureMinutes: facts.leisureMinutes, calendar: calendar) {
            return .tomorrow
        }
        return nil
    }

    /// Sunday from the evening start, and Monday morning.
    static func isWeekReviewTime(now: Date, leisureMinutes: Int, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: now)
        if weekday == 1 {
            return DayTimeline.isEvening(now: now, leisureMinutes: leisureMinutes, calendar: calendar)
        }
        return weekday == 2 && calendar.component(.hour, from: now) < mondayMorningEnd
    }

    /// The links under the page: what is not already shown as a card.
    struct QuietLinks: Equatable {
        var weekReview: Bool
        var setGoal: Bool
    }

    static func quietLinks(
        prominent: Prompt?, hasWeekData: Bool, hasGoal: Bool, isConfigured: Bool
    ) -> QuietLinks {
        QuietLinks(
            weekReview: hasWeekData && prominent != .weekReview,
            setGoal: isConfigured && !hasGoal
        )
    }
}
