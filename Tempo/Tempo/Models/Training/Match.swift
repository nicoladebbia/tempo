//
// Match.swift
// Tempo
//
// A specific, DATED match on the calendar (docs/INTELLIGENT_TRAINING_SYSTEM.md
// §9 D3, §14 mid-week-match trigger). Distinct from the recurring weekday
// `footballDays` bitmask in UserSettings: footballDays = "I usually play on
// Tue/Thu" (training cadence); a Match = "there is a game on Saturday the 14th"
// (a fixed fixture the surrounding days must be periodized around).
//
// Why both exist: the recurring days drive the steady-state week template; a
// dated Match is the mid-week trigger (§14.2) that re-shapes the surrounding
// days — T-1 leg-protection and (when present) match-day itself — even when it
// falls on a day that isn't a usual football day.
//
// The match feeds two already-built seams that were fed `nil` until D3:
//   • ReadinessPicture.daysUntilNextMatch (the brain's CONTEXT block, the
//     T-1/T-0 prompt lines, DailyCoachPrompt.exemplarPreMatch)
//   • The deterministic week planner's T-1 leg-swap (TrainingEngine), which
//     today keys only off recurring footballDays.
//
// All fields additive/optional per the single-V1-schema migration rule (§10).
//

import Foundation
import SwiftData

// MARK: - Match

@Model
final class Match {
    @Attribute(.unique)
    var id: UUID

    /// Kickoff. Stored as the exact instant the user picked; the start-of-day is
    /// what the T-1/T-0 day math uses (`dayKey`), so a 7PM and a 9AM kickoff on
    /// the same date are the same "match day" for periodization.
    var kickoff: Date

    /// Optional opponent label for the card ("vs Inter Miami"). nil → "Match".
    var opponent: String?

    /// Competitive fixture vs friendly/scrimmage. Competitive matches get the
    /// full taper (T-1 no heavy legs); this flag lets a future refinement soften
    /// the protection for a friendly without a schema change. Defaults true
    /// (protect by default — the safe assumption).
    var isCompetitive: Bool

    var createdAt: Date

    init(
        kickoff: Date,
        opponent: String? = nil,
        isCompetitive: Bool = true,
        createdAt: Date = Date()
    ) {
        id = UUID()
        self.kickoff = kickoff
        self.opponent = opponent
        self.isCompetitive = isCompetitive
        self.createdAt = createdAt
    }

    // MARK: - Computed

    /// Start-of-day of the kickoff — the unit all periodization math uses.
    @Transient
    var dayKey: Date {
        Calendar.current.startOfDay(for: kickoff)
    }
}

// MARK: - MatchSchedule

/// Pure helpers over a set of match day-keys. Kept free of @Model and of an
/// implicit "today" so they unit-test cleanly; the ViewModel passes `now`.
enum MatchSchedule {
    /// Whole days from the start-of-`from` to the next match at/after `from`.
    /// 0 = a match is TODAY, 1 = TOMORROW, nil = no upcoming match.
    /// `kickoffs` may be unsorted and may contain past matches; both are handled.
    static func daysUntilNextMatch(kickoffs: [Date], from: Date, calendar: Calendar = .current) -> Int? {
        let today = calendar.startOfDay(for: from)
        let upcoming = kickoffs
            .map { calendar.startOfDay(for: $0) }
            .filter { $0 >= today }
            .sorted()
        guard let next = upcoming.first else {
            return nil
        }
        return calendar.dateComponents([.day], from: today, to: next).day
    }

    /// True if `date`'s start-of-day is exactly one day before a match day —
    /// the T-1 protection window. Used to extend the engine's T-1 leg-swap to
    /// dated matches (not just recurring football weekdays).
    static func isTMinus1(date: Date, matchDayKeys: Set<Date>, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else {
            return false
        }
        return matchDayKeys.contains(tomorrow)
    }

    /// True if `date` is itself a match day (T-0).
    static func isMatchDay(date: Date, matchDayKeys: Set<Date>, calendar: Calendar = .current) -> Bool {
        matchDayKeys.contains(calendar.startOfDay(for: date))
    }
}
