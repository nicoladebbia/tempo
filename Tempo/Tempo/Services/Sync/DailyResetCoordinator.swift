//
// DailyResetCoordinator.swift
// Tempo
//
// Created by Tempo on 09/05/2026.
//
//

import Foundation
import os
import SwiftData

// MARK: - DailyResetCoordinator

// Runs end-of-day finalization without requiring the user to open the app.
// Triggered by BackgroundSyncService.handleDailyReset (BGProcessingTaskRequest)
// shortly after local midnight, OR opportunistically on first foreground of
// a new day.
//
// Per STATE_MACHINES.md §3 (review state) and §7 (streak broken/preserved):
//  - Yesterday's DailyAccountability gets its score finalized.
//  - Overall + per-habit streaks are advanced or broken/freezed.
//  - Today's DailyAccountability is created so the morning briefing has data.

enum DailyResetCoordinator {
    private static let logger = Logger(subsystem: "app.tempo", category: "DailyReset")
    private static let lastRunKey = "tempo.dailyReset.lastRun"
    private static let skipBackfillKey = "tempo.skipBackfill.completed"

    /// One-shot migration: NonNegotiableProgress entries that look skipped
    /// under the legacy sentinel encoding (isCompleted == true with
    /// currentValue < targetValue) get wasSkipped = true. Idempotent —
    /// guarded by a UserDefaults flag.
    @MainActor
    static func backfillWasSkippedIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: skipBackfillKey) else {
            return
        }
        let context = container.mainContext
        let descriptor = FetchDescriptor<NonNegotiableProgress>()
        let rows = (try? context.fetch(descriptor)) ?? []
        var updated = 0
        for row in rows where row.isCompleted
            && !row.wasSkipped
            && row.currentValue < row.targetValue
        {
            row.wasSkipped = true
            updated += 1
        }
        if updated > 0 {
            try? context.save()
        }
        defaults.set(true, forKey: skipBackfillKey)
        logger.info("wasSkipped backfill complete (\(updated) rows updated)")
    }

    /// Run a finalize cycle for any calendar day strictly older than today
    /// that has a non-finalized DailyAccountability record. Idempotent — calling
    /// twice in the same calendar day is a no-op after the first run.
    @MainActor
    static func runIfNeeded(container: ModelContainer) async {
        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: Date())

        if let last = defaults.object(forKey: lastRunKey) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today)
        {
            logger.debug("Daily reset already ran today, skipping")
            return
        }

        let context = container.mainContext
        let engine = AccountabilityEngine()

        // Finalize every prior-day DailyAccountability that hasn't been scored.
        let descriptor = FetchDescriptor<DailyAccountability>(
            sortBy: [SortDescriptor(\DailyAccountability.date, order: .reverse)]
        )
        let allDays = (try? context.fetch(descriptor)) ?? []
        let priorDays = allDays.filter { $0.date < today }

        for accountability in priorDays where accountability.accountabilityScore == 0 {
            accountability.accountabilityScore = engine.calculateDailyScore(
                accountability: accountability
            )
        }

        // Update overall streak using yesterday's outcome.
        if let yesterday = priorDays.first {
            let overallStreak = ensureStreak(type: .overall, in: context)
            engine.updateStreak(
                streak: overallStreak,
                dayCompleted: yesterday.allComplete,
                override: nil,
                modelContext: context
            )

            // Per-habit streaks (study/training/meals).
            let habitTypes: [(NonNegotiableType, StreakType)] = [
                (.study, .study),
                (.train, .training),
                (.meals, .meals),
            ]
            for (nnType, streakType) in habitTypes {
                let streak = ensureStreak(type: streakType, in: context)
                let progress = (yesterday.nonNegotiableProgress ?? [])
                    .first(where: { $0.nonNegotiable?.type == nnType })
                let dayDone = progress?.isCompleted ?? false
                engine.updateStreak(
                    streak: streak,
                    dayCompleted: dayDone,
                    override: nil,
                    modelContext: context
                )
            }
        }

        // Ensure today's DailyAccountability exists so the morning briefing
        // and dashboard land on a populated record.
        _ = engine.loadTodayNonNegotiables(modelContext: context)

        // Coach Agent — nightly behavior observation + preference decay.
        // Reads PlannedMeal vs MealLog for the trailing 7 days, mints
        // observed preferences, reinforces existing ones, and decays the
        // rest. Per docs/COACH_AGENT.md.
        BehaviorObserver.run(context: context)

        // Coach Agent — purge ended conversations older than 30 days. We
        // keep the extracted preferences (they live in LearnedPreference)
        // but the raw transcript bytes pile up fast and aren't useful
        // long-term. Active conversations (endedAt == nil) are never
        // purged regardless of age — that's a stuck session, not stale
        // history.
        if let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: today) {
            let endedDesc = FetchDescriptor<CoachConversation>(
                predicate: #Predicate<CoachConversation> { $0.endedAt != nil }
            )
            if let ended = try? context.fetch(endedDesc) {
                let stale = ended.filter { ($0.endedAt ?? Date.distantFuture) < cutoff }
                for convo in stale {
                    context.delete(convo)
                }
                if !stale.isEmpty {
                    logger.info("Purged \(stale.count) stale coach conversation(s) (>30 days)")
                }
            }
        }

        try? context.save()
        defaults.set(today, forKey: lastRunKey)
        logger.info("Daily reset complete for \(priorDays.count) prior day(s)")
    }

    @MainActor
    private static func ensureStreak(type: StreakType, in context: ModelContext) -> Streak {
        let raw = type.rawValue
        let descriptor = FetchDescriptor<Streak>(
            predicate: #Predicate { $0.typeRaw == raw }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let streak = Streak(type: type)
        context.insert(streak)
        return streak
    }
}
