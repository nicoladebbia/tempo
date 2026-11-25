//
// WeekShare.swift
// Tempo
//
// The "Share this week" card from the week in review. The sessions and the study
// minutes are the ones the review page shows; the XP is what the Arena keeps for
// the same Monday-to-Sunday week (the XP rows), so the card says what Arena says.
//

import Foundation
import SwiftData

// MARK: - WeekShare

enum WeekShare {
    /// XP earned in the seven days from `weekStart`, from the stored XP rows.
    @MainActor
    static func xp(in context: ModelContext, weekStart: Date, calendar: Calendar = ArenaCalendar.calendar()) -> Int {
        let start = calendar.startOfDay(for: weekStart)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else {
            return 0
        }
        let descriptor = FetchDescriptor<XPEvent>(predicate: #Predicate { $0.date >= start && $0.date < end })
        return ((try? context.fetch(descriptor)) ?? []).reduce(0) { $0 + $1.amount }
    }

    /// The card for this week's review. No rank: Today does not know the friends board.
    static func card(for review: WeekReview, xp: Int) -> ShareCardContent {
        .week(
            xp: max(0, xp), workouts: review.thisWeek.sessions, studyMinutes: review.thisWeek.studyMinutes,
            weekStart: review.weekStart
        )
    }
}
