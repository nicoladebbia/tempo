//
// WhoopDemoDataCleanup.swift
// Tempo
//
// One-shot removal of Whoop demo-mode data that older builds persisted as if
// it were real (before WhoopServiceProtocol.providesRealData gated writes).
// Demo rows carry MockWhoopService's exact constants, so they're matched by
// that full signature — a real Whoop day never hits every value at once.
//
// Removes: demo DailyRecovery rows (+ cascaded prescriptions), the AI daily
// sessions built on those days, and the mock soccer ActivitySession (reverting
// the plan it auto-completed). Resets WhoopConnection.didBackfill so a later
// real connection still imports 30 days of history.
//

import Foundation
import os
import SwiftData

enum WhoopDemoDataCleanup {
    private static let doneKey = "tempo.whoopDemoCleanup.v1"
    private static let logger = Logger(subsystem: "app.tempo", category: "WhoopDemoCleanup")

    struct Result: Equatable {
        var recoveries = 0
        var dailySessions = 0
        var activities = 0
        var plansReverted = 0
    }

    /// Runs once per install (flagged in UserDefaults).
    @MainActor
    static func runIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else {
            return
        }
        let context = container.mainContext
        let result = clean(context: context)
        if result != Result() {
            do {
                try context.save()
            } catch {
                // Leave the flag unset so the next launch retries.
                logger.error("Demo cleanup save failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        defaults.set(true, forKey: doneKey)
        logger
            .info(
                "Demo cleanup: \(result.recoveries) recoveries, \(result.dailySessions) sessions, \(result.activities) activities, \(result.plansReverted) plans"
            )
    }

    /// Deletes demo rows in `context` (does not save). Internal for tests.
    @MainActor
    static func clean(context: ModelContext) -> Result {
        var result = Result()

        // Narrow in the store on the score, match the full signature in memory
        // (a compound #Predicate over optionals times out the type checker).
        let recoveries = ((try? context.fetch(FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.recoveryScore == 72.0 }
        ))) ?? []).filter(isDemoRecovery)
        let cal = Calendar.current
        let demoDays = Set(recoveries.map { cal.startOfDay(for: $0.date) })
        for row in recoveries {
            context.delete(row)
        }
        result.recoveries = recoveries.count

        if !demoDays.isEmpty {
            // The daily coach ran on those fake signals — drop its output and
            // its once-per-day marker so today can rerun on real data.
            let sessions = ((try? context.fetch(FetchDescriptor<DailySession>())) ?? [])
                .filter { demoDays.contains(cal.startOfDay(for: $0.date)) }
            for session in sessions {
                context.delete(session)
            }
            result.dailySessions = sessions.count
            let demoKeys = Set(demoDays.map { AIProgramPlanner.isoDay($0) })
            for profile in (try? context.fetch(FetchDescriptor<AdaptiveProfile>())) ?? [] {
                if let key = profile.lastDailySessionDayKey, demoKeys.contains(key) {
                    profile.lastDailySessionDayKey = nil
                }
            }
            // Demo backfill set this after importing a single mock day.
            for connection in (try? context.fetch(FetchDescriptor<WhoopConnection>())) ?? [] {
                connection.didBackfill = false
            }
        }

        let activities = ((try? context.fetch(FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.source == "whoop" && $0.sportID == 1 }
        ))) ?? []).filter(isDemoActivity)
        for activity in activities {
            if let plan = plan(id: activity.workoutPlanID, in: context),
               plan.status == WorkoutStatus.completed
            {
                plan.status = WorkoutStatus.planned
                plan.finishedAt = nil
                result.plansReverted += 1
            }
            context.delete(activity)
        }
        result.activities = activities.count
        return result
    }

    // MARK: - MockWhoopService signatures

    private static func isDemoRecovery(_ row: DailyRecovery) -> Bool {
        row.recoveryScore == 72.0 && row.hrvRmssd == 48.0 && row.restingHR == 62.0
            && row.spo2 == 97.5 && row.skinTemp == 33.2
    }

    private static func isDemoActivity(_ row: ActivitySession) -> Bool {
        row.strain == 12.4 && row.caloriesBurned == 480.0 && row.durationMinutes == 62.0
            && row.averageHeartRate == 135.0
    }

    @MainActor
    private static func plan(id: UUID?, in context: ModelContext) -> WorkoutPlan? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<WorkoutPlan>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
}
