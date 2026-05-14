//
// DayPlanner.swift
// Tempo
//
// Rule-based daily plan solver. Per docs/INTELLIGENCE_REMEDIATION_PLAN.md §9.
//
// **Design choice locked with the advisor:** PlannedMeal / WorkoutPlan /
// EventKit are the source of truth for *what* and *when*. The §7 AI routes
// (training-program, meal-timing, study-schedule) only supply copy. That
// keeps the solver deterministic, fully offline-capable, and immune to
// AI-meal-source ↔ local-meal-source drift.
//
// The solver is pure: callers fetch inputs from SwiftData / CalendarService
// and pass value types in. No SwiftData reach inside; no Calendar/EventKit
// calls; no Date() reads other than via `now`. Unit-testable.
//

import Foundation

// MARK: - DayPlannerInput

/// Everything the solver needs to lay out one day. Values are pre-resolved
/// into the local-time-of-day domain (minute-of-day Ints) so the solver
/// never has to think in absolute Dates.
struct DayPlannerInput: Sendable {
    /// The calendar day being planned. Used only to attach to the
    /// produced DayPlan, never for solver math.
    let date: Date

    /// User's planned wake time (minutes from midnight). Drives the
    /// earliest free-window boundary.
    let wakeMinute: Int

    /// User's bedtime fence (minutes from midnight). The sleep block
    /// runs from `bedtimeMinute` to `wakeMinute + 1440` conceptually,
    /// but is rendered as a single end-of-day block in the timeline.
    let bedtimeMinute: Int

    /// Today's fixed external events, already filtered to non-all-day
    /// EventKit entries. The solver classifies these into class/exam/
    /// work/football/free using the kind hints supplied here.
    let fixedBlocks: [FixedBlock]

    /// Today's planned meals — minute-of-day boundaries derived from
    /// `PlannedMeal.scheduledTime` + `eatDurationMinutes`.
    let mealBlocks: [PlannedBlock]

    /// Today's workout — start derived from existing rules in
    /// `TrainingEngine` (callers can pass `.evening` default).
    let workoutBlock: PlannedBlock?

    /// Study sessions from the existing Pomodoro generator. Each block
    /// is one full Pomodoro window (length matches user's
    /// `studySessionLengthMinutes`).
    let studyBlocks: [PlannedBlock]

    /// Recovery / mobility block when RecoveryEngine prescribed one.
    let recoveryBlock: PlannedBlock?
}

// MARK: - FixedBlock

/// External calendar event reduced to the fields the solver needs. Kind
/// is resolved by the caller (CalendarService can already detect classes,
/// exams, football) so the solver doesn't reach into EventKit semantics.
struct FixedBlock: Sendable, Equatable {
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int
    let title: String
    let kind: TimeBlockKind  // class / exam / work / football
    let sourceId: String?    // EKEvent.eventIdentifier
}

// MARK: - PlannedBlock

/// One locally-owned planned event (PlannedMeal / WorkoutPlan / study
/// Pomodoro / recovery). The solver takes these as already-placed.
struct PlannedBlock: Sendable, Equatable {
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int
    let title: String
    let sourceId: String?  // PlannedMeal.id / WorkoutPlan.id / etc.
}

// MARK: - DayPlanner

enum DayPlanner {

    /// Produce the TimeBlock list for one day. Caller is responsible for
    /// wrapping the result in a DayPlan and inserting into SwiftData.
    ///
    /// Placement order (deterministic):
    ///   1. Fixed blocks (class/exam/work/football) — never moved.
    ///   2. Planned meals — kept at their PlannedMeal.scheduledTime.
    ///      Conflicts with fixed blocks are flagged but not auto-resolved
    ///      (the FuelMealScheduleAnnotator handles that surfacing already).
    ///   3. Workout — kept at its declared time.
    ///   4. Study Pomodoros — only placed in free windows; conflicts
    ///      with fixed blocks cause the session to be dropped from the
    ///      timeline (the user keeps the original study row).
    ///   5. Recovery / mobility block — same rules as study.
    ///   6. Sleep fence — `bedtimeMinute` → 1440.
    ///   7. Free blocks — fill remaining gaps between `wakeMinute` and
    ///      `bedtimeMinute`. Gaps under 15 min are absorbed into
    ///      adjacent blocks (a 7-minute free block is noise, not signal).
    static func solve(_ input: DayPlannerInput) -> [TimeBlock] {
        var placed: [TimeBlock] = []

        // 1. Fixed blocks.
        for fixed in input.fixedBlocks {
            placed.append(TimeBlock(
                kind: fixed.kind,
                startMinuteOfDay: fixed.startMinuteOfDay,
                endMinuteOfDay: fixed.endMinuteOfDay,
                title: fixed.title,
                sourceId: fixed.sourceId
            ))
        }

        // 2. Planned meals. Conflicts with fixed blocks are surfaced
        //    elsewhere — we still render the meal block at its declared
        //    time so the user sees the clash on the timeline.
        for meal in input.mealBlocks {
            placed.append(TimeBlock(
                kind: .meal,
                startMinuteOfDay: meal.startMinuteOfDay,
                endMinuteOfDay: meal.endMinuteOfDay,
                title: meal.title,
                sourceId: meal.sourceId
            ))
        }

        // 3. Workout.
        if let w = input.workoutBlock {
            placed.append(TimeBlock(
                kind: .training,
                startMinuteOfDay: w.startMinuteOfDay,
                endMinuteOfDay: w.endMinuteOfDay,
                title: w.title,
                sourceId: w.sourceId
            ))
        }

        // 4 + 5. Study + recovery — drop if they overlap a fixed block.
        let fixedRanges = input.fixedBlocks.map { ($0.startMinuteOfDay, $0.endMinuteOfDay) }
        for study in input.studyBlocks where !overlapsAny(start: study.startMinuteOfDay, end: study.endMinuteOfDay, ranges: fixedRanges) {
            placed.append(TimeBlock(
                kind: .study,
                startMinuteOfDay: study.startMinuteOfDay,
                endMinuteOfDay: study.endMinuteOfDay,
                title: study.title,
                sourceId: study.sourceId
            ))
        }
        if let r = input.recoveryBlock,
           !overlapsAny(start: r.startMinuteOfDay, end: r.endMinuteOfDay, ranges: fixedRanges)
        {
            placed.append(TimeBlock(
                kind: .recovery,
                startMinuteOfDay: r.startMinuteOfDay,
                endMinuteOfDay: r.endMinuteOfDay,
                title: r.title,
                sourceId: r.sourceId
            ))
        }

        // 6. Sleep fence. Bedtime → end of day; the morning sleep tail
        //    (00:00 → wakeMinute) is rendered as a separate sleep block
        //    so the timeline reads naturally top-to-bottom.
        if input.wakeMinute > 0 {
            placed.append(TimeBlock(
                kind: .sleep,
                startMinuteOfDay: 0,
                endMinuteOfDay: input.wakeMinute,
                title: "Sleep"
            ))
        }
        if input.bedtimeMinute < 1440 {
            placed.append(TimeBlock(
                kind: .sleep,
                startMinuteOfDay: input.bedtimeMinute,
                endMinuteOfDay: 1440,
                title: "Sleep"
            ))
        }

        // 7. Fill gaps in [wakeMinute, bedtimeMinute] with `free` blocks.
        let dayBlocks = placed.sorted(by: { $0.startMinuteOfDay < $1.startMinuteOfDay })
        var cursor = input.wakeMinute
        var freeBlocks: [TimeBlock] = []
        for block in dayBlocks where block.startMinuteOfDay >= input.wakeMinute && block.endMinuteOfDay <= input.bedtimeMinute {
            if block.startMinuteOfDay > cursor {
                let gap = block.startMinuteOfDay - cursor
                if gap >= 15 {
                    freeBlocks.append(TimeBlock(
                        kind: .free,
                        startMinuteOfDay: cursor,
                        endMinuteOfDay: block.startMinuteOfDay,
                        title: "Free"
                    ))
                }
            }
            cursor = max(cursor, block.endMinuteOfDay)
        }
        if input.bedtimeMinute > cursor + 15 {
            freeBlocks.append(TimeBlock(
                kind: .free,
                startMinuteOfDay: cursor,
                endMinuteOfDay: input.bedtimeMinute,
                title: "Free"
            ))
        }

        return (placed + freeBlocks).sorted(by: { $0.startMinuteOfDay < $1.startMinuteOfDay })
    }

    // MARK: - Helpers

    private static func overlapsAny(start: Int, end: Int, ranges: [(Int, Int)]) -> Bool {
        ranges.contains(where: { r in start < r.1 && end > r.0 })
    }
}

// MARK: - Reason

/// Telemetry hint passed into the re-plan caller so the eventual analytics
/// pipeline can attribute regenerations.
enum DayPlanReason: String, Sendable {
    case initial
    case calendarChanged       = "calendar_changed"
    case whoopSynced           = "whoop_synced"
    case workoutLogged         = "workout_logged"
    case mealEatenOffSchedule  = "meal_eaten_off_schedule"
    case userRequested         = "user_requested"
}
