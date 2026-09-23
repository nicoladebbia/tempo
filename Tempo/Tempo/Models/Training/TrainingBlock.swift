//
// TrainingBlock.swift
// Tempo
//
// The current training-block emphasis (docs/INTELLIGENT_TRAINING_SYSTEM.md
// §14 Decision 1, §14.1): Nicola DECLARES the emphasis manually ("next 4
// weeks = physique" / "now = soccer block"); the system periodizes within it,
// holding the non-emphasis goal at maintenance (§12 interference rules). The
// emphasis is NOT auto-driven by the match calendar — the calendar drives
// match-protection and taper INSIDE whatever block is active.
//
// The block feeds two seams that ran on a hardcoded default until D3 part 2:
//   • DailyCoachPrompt's "Block emphasis:" CONTEXT line (was "physique
//     (default)" verbatim — the system prompt already teaches the
//     emphasis-week semantics; the user message now carries the real value)
//   • AIProgramPlanner.planWeek(goal:) (was the literal "hypertrophy")
//
// Default before a block is ever set: physique — the current de-facto
// behavior, so an untouched install behaves exactly as before.
//
// All fields additive per the single-V1-schema migration rule (§10).
//

import Foundation
import SwiftData

// MARK: - BlockEmphasis

/// The two goals of the dual-goal model (§12). One is primary per block;
/// the other is held at maintenance — never both maximized in a microcycle.
enum BlockEmphasis: String, Codable, Sendable, CaseIterable {
    case physique
    case soccer

    var displayName: String {
        switch self {
        case .physique: "Physique"
        case .soccer: "Soccer"
        }
    }

    /// The `goal:` string handed to the weekly AI program planner. Physique
    /// keeps the exact pre-D3 literal ("hypertrophy") so the weekly prompt is
    /// unchanged for the default case.
    var weeklyGoal: String {
        switch self {
        case .physique: "hypertrophy"
        case .soccer: "soccer performance — speed/conditioning primary, strength at maintenance"
        }
    }
}

// MARK: - TrainingBlock

@Model
final class TrainingBlock {
    @Attribute(.unique)
    var id: UUID

    /// Raw storage for `emphasis` (same enum-storage pattern as WorkoutPlan.typeRaw).
    var emphasisRaw: String

    /// First day the block applies (start-of-day is the unit, like Match.dayKey).
    var startDate: Date

    /// Last day the block applies, INCLUSIVE. nil = open-ended ("now = soccer
    /// block" with no declared end) — runs until a newer block supersedes it.
    var endDate: Date?

    var createdAt: Date

    init(
        emphasis: BlockEmphasis,
        startDate: Date,
        endDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        id = UUID()
        emphasisRaw = emphasis.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
    }

    @Transient
    var emphasis: BlockEmphasis {
        get { BlockEmphasis(rawValue: emphasisRaw) ?? .physique }
        set { emphasisRaw = newValue.rawValue }
    }

    @Transient
    var span: BlockSpan {
        BlockSpan(emphasis: emphasis, start: startDate, end: endDate)
    }
}

// MARK: - BlockSpan

/// Value mirror of a TrainingBlock's scheduling fields, so the selection math
/// stays free of @Model (same separation as MatchSchedule over kickoff Dates).
struct BlockSpan: Equatable, Sendable {
    let emphasis: BlockEmphasis
    let start: Date
    /// Inclusive last day; nil = open-ended.
    let end: Date?
}

// MARK: - TrainingBlockSchedule

enum TrainingBlockSchedule {
    /// The emphasis in force on `date`, or nil when no block covers it (caller
    /// defaults to .physique — the pre-D3 behavior).
    ///
    /// A block covers `date` when startOfDay(start) <= startOfDay(date) and
    /// (end == nil or startOfDay(date) <= startOfDay(end)) — both boundary
    /// days inclusive. Overlaps resolve latest-start-wins: declaring a new
    /// block today supersedes the old one without requiring it to be closed.
    static func currentEmphasis(
        spans: [BlockSpan],
        on date: Date,
        calendar: Calendar = .current
    ) -> BlockEmphasis? {
        let day = calendar.startOfDay(for: date)
        return spans
            .filter { span in
                calendar.startOfDay(for: span.start) <= day
                    && (span.end.map { day <= calendar.startOfDay(for: $0) } ?? true)
            }
            .max { $0.start < $1.start }?
            .emphasis
    }
}
