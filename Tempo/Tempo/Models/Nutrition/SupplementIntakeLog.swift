//
// SupplementIntakeLog.swift
// Tempo
//
// One row per supplement actually TAKEN on a given day — the user tapping the
// checkmark on the Today "supplements" card. A row's existence means "taken";
// undo deletes the row. Kept separate from the plan's `supplementDecisions`
// (which is the AI's take/skip recommendation) because:
//   - the plan is REGENERATED weekly, which would wipe taken-history;
//   - this is a user-action log, not a recommendation;
//   - it sets up future adherence trends ("took creatine 5/7 days").
//
// Keyed by start-of-day DATE (NOT weekday) — a calendar-day fact, so last
// Monday's check never lights up this Monday. The join back to a decision is
// the supplement NAME string (the only shared key); renaming a supplement
// orphans its history, which is acceptable.
//

import Foundation
import SwiftData

@Model
final class SupplementIntakeLog {
    @Attribute(.unique)
    var id: UUID

    /// Matches `Supplement.name` / `SupplementDecision.name`.
    var supplementName: String

    /// Calendar day this was taken, normalized to start-of-day.
    var day: Date

    /// Wall-clock moment the user tapped "taken".
    var takenAt: Date

    init(
        id: UUID = UUID(),
        supplementName: String,
        day: Date,
        takenAt: Date = Date()
    ) {
        self.id = id
        self.supplementName = supplementName
        self.day = Calendar.current.startOfDay(for: day)
        self.takenAt = takenAt
    }
}
