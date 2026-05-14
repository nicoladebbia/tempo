//
// DayPlan.swift
// Tempo
//
// Time-blocked day plan. Per docs/INTELLIGENCE_REMEDIATION_PLAN.md §9.
// Produced by `DayPlanner` from the existing local sources of truth
// (PlannedMeal, WorkoutPlan, CalendarService) and hydrated with AI copy.
//

import Foundation
import SwiftData

// MARK: - TimeBlockKind

/// One of the 10 stable categories a time block can carry. The order here
/// is intentional — the solver places fixed blocks first (class, exam,
/// work, football), then computed blocks (training, study, meal, recovery),
/// then leaves `free` for everything else. `sleep` is a fence at the end
/// of the day.
enum TimeBlockKind: String, Codable, CaseIterable, Sendable {
    case `class`
    case exam
    case work
    case football
    case training
    case study
    case meal
    case recovery
    case sleep
    case free

    /// Blocks the user can't move because they come from an external
    /// system (EventKit). The solver never reflows these.
    var isFixed: Bool {
        switch self {
        case .class, .exam, .work, .football: true
        default: false
        }
    }

    /// SF Symbol used by the timeline view's leading rail.
    var symbolName: String {
        switch self {
        case .class: "graduationcap.fill"
        case .exam: "doc.text.fill"
        case .work: "briefcase.fill"
        case .football: "sportscourt.fill"
        case .training: "dumbbell.fill"
        case .study: "book.fill"
        case .meal: "fork.knife"
        case .recovery: "leaf.fill"
        case .sleep: "moon.fill"
        case .free: "circle.dashed"
        }
    }
}

// MARK: - DayPlan

/// One row per (user, calendar day). Recreated on every solver run — the
/// solver deletes the existing row for the day and inserts a fresh one
/// rather than diff-patching, since block boundaries can shift in
/// non-trivial ways when the user logs a workout off-schedule or a new
/// calendar event appears.
@Model
final class DayPlan {

    @Attribute(.unique)
    var id: UUID

    /// Calendar-day boundary (startOfDay). The (date) tuple is the natural
    /// uniqueness key but @Attribute(.unique) on Date is risky across
    /// time zones, so we enforce uniqueness in the solver by deleting
    /// before insert.
    var date: Date

    /// When the solver last produced this plan. Used by the UI to show
    /// "regenerated 3 min ago" and by the AI-hydration step to know
    /// whether cached copy is still applicable.
    var generatedAt: Date

    /// Cascading delete keeps the join tidy when a plan is regenerated.
    @Relationship(deleteRule: .cascade, inverse: \TimeBlock.plan)
    var blocks: [TimeBlock]

    init(
        id: UUID = UUID(),
        date: Date,
        generatedAt: Date = Date(),
        blocks: [TimeBlock] = []
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.generatedAt = generatedAt
        self.blocks = blocks
    }
}

// MARK: - TimeBlock

@Model
final class TimeBlock {

    @Attribute(.unique)
    var id: UUID

    var kindRaw: String

    /// Minutes from midnight in the plan's local calendar day. 0..<1440.
    var startMinuteOfDay: Int

    /// Minutes from midnight, exclusive. Must be > start. Wrap-around
    /// past midnight (e.g. 23:30–01:00) is not modelled — sleep is
    /// represented as a fence at end-of-day, not a crossing block.
    var endMinuteOfDay: Int

    /// What the timeline row shows ("STAT 101", "Push day", "Lunch").
    var title: String

    /// AI-generated rationale or coaching prose. Nil when AI hydration
    /// hasn't completed or has failed. The view falls back to title.
    var copy: String?

    /// Stable identifier of the originating local row (PlannedMeal.id /
    /// WorkoutPlan.id / EKEvent.eventIdentifier). Lets the UI tap-route
    /// from a block to the underlying record's detail screen.
    var sourceId: String?

    @Relationship(deleteRule: .nullify)
    var plan: DayPlan?

    @Transient
    var kind: TimeBlockKind {
        get { TimeBlockKind(rawValue: kindRaw) ?? .free }
        set { kindRaw = newValue.rawValue }
    }

    @Transient
    var durationMinutes: Int { max(0, endMinuteOfDay - startMinuteOfDay) }

    init(
        id: UUID = UUID(),
        kind: TimeBlockKind,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        title: String,
        copy: String? = nil,
        sourceId: String? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.title = title
        self.copy = copy
        self.sourceId = sourceId
    }
}
