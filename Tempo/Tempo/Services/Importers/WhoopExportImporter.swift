//
// WhoopExportImporter.swift
// Tempo
//
// SwiftData writes for the Whoop account-data export (parsing lives in
// WhoopExportParser — pure). Strictly ADDITIVE: a day that already has a
// DailyRecovery row is never touched (live API data wins over the export),
// and a workout within ±2 min of an existing ActivitySession start is a
// duplicate and skipped. JournalInsights are derived data and replaced
// wholesale (the export is the only source — nothing to merge with).
//
// After a successful import the venue learner recomputes (432 historical
// workouts = instant §16 patterns) and the standard change notifications fire
// so every reading surface refreshes.
//

import Foundation
import SwiftData

enum WhoopExportImporter {
    struct Summary: Equatable, Sendable {
        var cyclesImported = 0
        var cyclesSkipped = 0
        var workoutsImported = 0
        var workoutsSkipped = 0
        var insightsComputed = 0
        var filesIgnored = 0

        var label: String {
            "\(cyclesImported) days + \(workoutsImported) workouts imported"
                + " (\(cyclesSkipped + workoutsSkipped) already present)"
                + (insightsComputed > 0 ? ", \(insightsComputed) journal patterns" : "")
        }
    }

    /// Imports any of the export's CSVs (identified by header, not filename —
    /// sleeps.csv is recognized and deliberately ignored; cycles carry the
    /// per-day sleep fields already).
    @MainActor
    static func importFiles(_ urls: [URL], modelContext: ModelContext) -> Summary {
        var summary = Summary()
        var journalRows: [WhoopExportParser.JournalRow] = []
        var cycleRows: [WhoopExportParser.CycleRow] = []

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let header = text.split(separator: "\n", maxSplits: 1).first else {
                summary.filesIgnored += 1
                continue
            }

            if header.contains("Recovery score %") {
                cycleRows = WhoopExportParser.cycles(fromCSV: text)
                importCycles(cycleRows, into: modelContext, summary: &summary)
            } else if header.contains("Activity Strain") {
                importWorkouts(WhoopExportParser.workouts(fromCSV: text), into: modelContext, summary: &summary)
            } else if header.contains("Question text") {
                journalRows = WhoopExportParser.journal(fromCSV: text)
            } else {
                summary.filesIgnored += 1 // sleeps.csv (or unknown) — by design
            }
        }

        if !journalRows.isEmpty {
            // Pair answers with the export's own recovery scores — the export
            // covers exactly the journal's date range.
            let recoveryByDay = Dictionary(
                cycleRows.map { ($0.date, $0.recoveryScore) },
                uniquingKeysWith: { a, _ in a }
            )
            summary.insightsComputed = replaceInsights(
                WhoopExportParser.correlations(journal: journalRows, recoveryByDay: recoveryByDay),
                in: modelContext
            )
        }

        try? modelContext.save()
        VenuePatternLearner.recompute(modelContext: modelContext)
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)

        #if DEBUG
            print("\(DebugTrace.prefix)[whoop_import] \(summary.label)")
        #endif
        return summary
    }

    // MARK: - Cycles → DailyRecovery (additive)

    @MainActor
    private static func importCycles(
        _ rows: [WhoopExportParser.CycleRow],
        into modelContext: ModelContext,
        summary: inout Summary
    ) {
        let existing = (try? modelContext.fetch(FetchDescriptor<DailyRecovery>())) ?? []
        var existingDays = Set(existing.map(\.date))

        for row in rows {
            guard !existingDays.contains(row.date) else {
                summary.cyclesSkipped += 1
                continue
            }
            existingDays.insert(row.date)
            modelContext.insert(DailyRecovery(
                date: row.date,
                recoveryScore: row.recoveryScore,
                hrvRmssd: row.hrv,
                restingHR: row.rhr,
                spo2: row.spo2,
                skinTemp: row.skinTemp,
                sleepHours: row.sleepHours,
                sleepScore: row.sleepPerformancePct,
                sleepEfficiency: row.efficiencyPct,
                sleepConsistency: row.consistencyPct,
                deepSleepMin: row.deepMin,
                remSleepMin: row.remMin,
                lightSleepMin: row.lightMin,
                awakeMin: row.awakeMin,
                sleepNeededBaseline: row.sleepNeedHours,
                sleepDebt: row.sleepDebtHours,
                respiratoryRate: row.respRate,
                strain: row.dayStrain,
                avgHR: row.avgHR,
                maxHR: row.maxHR,
                caloriesBurned: row.calories
            ))
            summary.cyclesImported += 1
        }
    }

    // MARK: - Workouts → ActivitySession (additive, ±2 min dedup)

    @MainActor
    private static func importWorkouts(
        _ rows: [WhoopExportParser.WorkoutRow],
        into modelContext: ModelContext,
        summary: inout Summary
    ) {
        let existing = (try? modelContext.fetch(FetchDescriptor<ActivitySession>())) ?? []
        var existingStarts = existing.map(\.startTime)

        for row in rows {
            let isDuplicate = existingStarts.contains { abs($0.timeIntervalSince(row.startTime)) < 120 }
            guard !isDuplicate else {
                summary.workoutsSkipped += 1
                continue
            }
            existingStarts.append(row.startTime)
            let session = ActivitySession(
                date: row.startTime,
                startTime: row.startTime,
                workoutType: row.workoutType,
                sportID: -1,
                source: "whoop_import",
                strain: row.strain,
                averageHeartRate: row.avgHR,
                maxHeartRate: row.maxHR,
                caloriesBurned: row.calories,
                durationMinutes: row.durationMin
            )
            if let z = row.zoneMinutes, z.count == 5 {
                session.zone1Min = z[0]
                session.zone2Min = z[1]
                session.zone3Min = z[2]
                session.zone4Min = z[3]
                session.zone5Min = z[4]
            }
            modelContext.insert(session)
            summary.workoutsImported += 1
        }
    }

    // MARK: - Journal → JournalInsight (replace wholesale)

    @MainActor
    private static func replaceInsights(
        _ correlations: [WhoopExportParser.HabitCorrelation],
        in modelContext: ModelContext
    ) -> Int {
        let stale = (try? modelContext.fetch(FetchDescriptor<JournalInsight>())) ?? []
        for row in stale { modelContext.delete(row) }
        for c in correlations {
            modelContext.insert(JournalInsight(
                question: c.question,
                yesCount: c.yesCount,
                noCount: c.noCount,
                yesMeanRecovery: c.yesMeanRecovery,
                noMeanRecovery: c.noMeanRecovery
            ))
        }
        return correlations.count
    }
}
