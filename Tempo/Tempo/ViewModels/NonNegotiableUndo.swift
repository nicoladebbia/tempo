//
// NonNegotiableUndo.swift
// Tempo
//
// What a non-negotiable looked like just before it was completed or skipped,
// so a few seconds later "Undo" puts back exactly that: the task, the day's
// unlock and the habit streak the tap moved. Taken before the change, applied
// only if the user asks.
//

import Foundation
import SwiftData

@MainActor
struct NonNegotiableUndo {
    private let progress: NonNegotiableProgress
    private let currentValue: Double
    private let isCompleted: Bool
    private let completedAt: Date?
    private let wasSkipped: Bool

    private let accountability: DailyAccountability?
    private let leisureUnlocked: Bool
    private let unlockedAt: Date?

    private let streak: Streak?
    private let streakCurrent: Int
    private let streakLongest: Int
    private let streakLastCompleted: Date?

    /// Reads the state that completing or skipping `progress` can change.
    init(
        progress: NonNegotiableProgress,
        accountability: DailyAccountability?,
        habitStreak: Streak?
    ) {
        self.progress = progress
        currentValue = progress.currentValue
        isCompleted = progress.isCompleted
        completedAt = progress.completedAt
        wasSkipped = progress.wasSkipped

        self.accountability = accountability
        leisureUnlocked = accountability?.leisureUnlocked ?? false
        unlockedAt = accountability?.unlockedAt

        streak = habitStreak
        streakCurrent = habitStreak?.currentCount ?? 0
        streakLongest = habitStreak?.longestCount ?? 0
        streakLastCompleted = habitStreak?.lastCompletedDate
    }

    /// Puts the task, the unlock and the streak back as they were.
    func apply(modelContext: ModelContext) {
        // The task may have been deleted while the toast was up: there is nothing to put back.
        guard !progress.isDeleted, progress.modelContext != nil else {
            return
        }
        progress.currentValue = currentValue
        progress.isCompleted = isCompleted
        progress.completedAt = completedAt
        progress.wasSkipped = wasSkipped

        if let accountability, !accountability.isDeleted, accountability.modelContext != nil {
            accountability.leisureUnlocked = leisureUnlocked
            accountability.unlockedAt = unlockedAt
        }
        if let streak, !streak.isDeleted, streak.modelContext != nil {
            streak.currentCount = streakCurrent
            streak.longestCount = streakLongest
            streak.lastCompletedDate = streakLastCompleted
        }
        try? modelContext.save()
    }
}
