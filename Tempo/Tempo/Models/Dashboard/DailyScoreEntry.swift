//
// DailyScoreEntry.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - Daily Score Entry

// Persists daily scores for 7-day sparkline trend display on the Dashboard.
// One entry per calendar day. Updated when the daily score changes significantly (>5 points)
// or at end-of-day via background task.

@Model
final class DailyScoreEntry {
    @Attribute(.unique)
    var id: UUID

    /// Calendar date (normalized to start of day).
    @Attribute(.unique)
    var date: Date

    /// Composite daily score (0-100).
    var score: Int

    /// Timestamp of last update.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        score: Int
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.score = score
        updatedAt = Date()
    }
}
