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

    /// Coach v2.1 — provider injected at app startup so the daily reset
    /// can grade pending outcomes. nil → skip the grader step (the
    /// observer + health-check + purge still run unconditionally).
    /// Per Phase 8a wiring. Set once from the app delegate / scene entry.
    @MainActor
    static var coachEvidenceProvider: (any OutcomeEvidenceProvider)?
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

        // Macro carryover capture (Phase F) — finalize each prior day's
        // (target − actual) into a 5-day-spread row and tick any active
        // rows forward. captureCarryoverIfNeeded is idempotent + handles
        // missing-plan / nothing-logged days defensively.
        if let cal = Optional(Calendar.current),
           let yesterday = cal.date(byAdding: .day, value: -1, to: today)
        {
            MacroCarryoverService.captureCarryoverIfNeeded(for: yesterday, in: context)
        }

        // Coach v2.1 maintenance — observer + health-check + grader (when
        // a provider is registered) + conversation purge.
        await runCoachMaintenance(in: context, today: today)

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

    /// Coach v2.1 maintenance — runs alongside the existing daily reset.
    ///
    ///   1) BehaviorObserver.observe — scans last 7 days of meals,
    ///      proposes/reinforces/flags observed preferences, applies
    ///      one day of decay across active rows.
    ///   2) PreferenceHealthCheck.scan — flags high-confidence prefs
    ///      contradicted by recent outcomes, clears flags when behavior
    ///      recovers.
    ///   3) Conversation purge — soft-deletes CoachConversation rows
    ///      older than 30 days unless isStarred=true.
    ///
    /// OutcomeGrader.run is intentionally NOT wired here — it needs a
    /// real OutcomeEvidenceProvider (HK + SwiftData reads) that lives
    /// in a follow-up commit. The grader runs cleanly via its own entry
    /// once that provider is built.
    @MainActor
    private static func runCoachMaintenance(
        in context: ModelContext,
        today: Date
    ) async {
        do {
            let observerReport = try BehaviorObserver.observe(
                modelContext: context,
                today: today
            )
            logger.info(
                "Coach observer: proposed=\(observerReport.proposed) reinforced=\(observerReport.reinforced) contradictionsFlagged=\(observerReport.contradictionsFlagged) decayed=\(observerReport.decayed) deactivated=\(observerReport.deactivatedByDecay)"
            )
        } catch {
            logger.error("Coach observer failed: \(error.localizedDescription)")
        }

        do {
            let healthReport = try PreferenceHealthCheck.scan(
                in: context,
                today: today
            )
            logger.info(
                "Coach health-check: flagged=\(healthReport.flagged) cleared=\(healthReport.clearedExistingFlag) examined=\(healthReport.examined)"
            )
        } catch {
            logger.error("Coach health-check failed: \(error.localizedDescription)")
        }

        // OutcomeGrader runs only when an evidence provider is registered
        // (set once at app startup by Phase 8 wiring). Without a provider
        // the grader can't fetch real evidence, so pending rows linger
        // until next run — harmless.
        if let provider = coachEvidenceProvider {
            do {
                let gradeReport = try await OutcomeGrader.run(
                    in: context,
                    today: today,
                    provider: provider
                )
                logger.info(
                    "Coach grader: graded=\(gradeReport.graded) skipped=\(gradeReport.skippedNotYetDue) unclear=\(gradeReport.unclearDueToMissingEvidence)"
                )
            } catch {
                logger.error("Coach grader failed: \(error.localizedDescription)")
            }
        }

        let purged = purgeStaleCoachConversations(in: context, today: today)
        if purged > 0 {
            logger.info("Coach purge: deleted \(purged) stale conversations")
        }
    }

    /// Internal helper extracted for testing. Returns the count of
    /// purged rows so callers (and tests) can log + assert.
    @MainActor
    @discardableResult
    static func purgeStaleCoachConversations(
        in context: ModelContext,
        today: Date,
        maxAgeDays: Int = 30
    ) -> Int {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -maxAgeDays, to: today) else {
            return 0
        }
        let descriptor = FetchDescriptor<CoachConversation>(
            predicate: #Predicate<CoachConversation> { conv in
                !conv.isStarred && conv.lastMessageAt < cutoff
            }
        )
        let stale = (try? context.fetch(descriptor)) ?? []
        for row in stale {
            context.delete(row)
        }
        return stale.count
    }
}
