//
// WeekOverWeekProgressLoader.swift
// Tempo
//
// Fetches the SwiftData rows `WeekOverWeekProgress` needs and turns them into
// its plain `Result` — the ModelContext-touching half of the pure comparator,
// same split as `TrainerReportSheet`'s own `fetchPlans`/`fetchPersonalRecords`
// static helpers feeding `TrainerReportBuilder`.
//

import Foundation
import SwiftData

// MARK: - WeekOverWeekProgressLoader

@MainActor
enum WeekOverWeekProgressLoader {
    /// `scopeRange` is the SAME strict scope window `TrainerReportBuilder
    /// .scheduleRange` computed for the report/recap — "this week's trainer
    /// sessions" IS that window. Every exercise/conditioning row logged
    /// anywhere strictly BEFORE it (any athlete session, any past weekly
    /// program) is fair game as the "previous" side of the comparison.
    static func load(scopeRange: ClosedRange<Date>, modelContext: ModelContext) -> WeekOverWeekProgress.Result {
        let lower = scopeRange.lowerBound
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: scopeRange.upperBound) ?? scopeRange.upperBound

        let currentHistoryDescriptor = FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate { $0.date >= lower && $0.date < upper }
        )
        let currentHistories = (try? modelContext.fetch(currentHistoryDescriptor)) ?? []
        let priorHistoryDescriptor = FetchDescriptor<ExerciseHistory>(predicate: #Predicate { $0.date < lower })
        let priorHistories = (try? modelContext.fetch(priorHistoryDescriptor)) ?? []
        let exercises = WeekOverWeekProgress.compareExercises(currentHistories: currentHistories, priorHistories: priorHistories)

        let currentResultsDescriptor = FetchDescriptor<ConditioningBlockResult>(
            predicate: #Predicate { $0.date >= lower && $0.date < upper }
        )
        let currentResults = (try? modelContext.fetch(currentResultsDescriptor)) ?? []
        let priorResultsDescriptor = FetchDescriptor<ConditioningBlockResult>(predicate: #Predicate { $0.date < lower })
        let priorResults = (try? modelContext.fetch(priorResultsDescriptor)) ?? []

        guard !currentResults.isEmpty, !priorResults.isEmpty else {
            return WeekOverWeekProgress.Result(exercises: exercises, conditioning: [])
        }

        let allPrograms = (try? modelContext.fetch(FetchDescriptor<TrainerProgram>())) ?? []
        let programsByID = Dictionary(uniqueKeysWithValues: allPrograms.map { ($0.id, $0) })

        let currentBlocks = currentResults.compactMap { snapshot(for: $0, programsByID: programsByID) }
        let priorBlocks = priorResults.compactMap { snapshot(for: $0, programsByID: programsByID) }
        let conditioning = WeekOverWeekProgress.compareConditioning(currentBlocks: currentBlocks, priorBlocks: priorBlocks)

        return WeekOverWeekProgress.Result(exercises: exercises, conditioning: conditioning)
    }

    /// Resolves a logged block back to its trainer-written label/prescription
    /// text via the `programSessionKey`'s `<programUUID>#weekIndex#dDayIndex`
    /// prefix — same parse `TrainerReportSheet.program(forSessionKey:)` and
    /// `StoredConditioningResults` both already use.
    private static func snapshot(
        for result: ConditioningBlockResult,
        programsByID: [UUID: TrainerProgram]
    ) -> WeekOverWeekProgress.ConditioningBlockSnapshot? {
        guard let sessionKey = result.programSessionKey,
              let programID = sessionKey.split(separator: "#").first.flatMap({ UUID(uuidString: String($0)) }),
              let program = programsByID[programID],
              let blockID = result.blockID
        else {
            return nil
        }
        let blocks = program.weeks.flatMap(\.days).flatMap(\.exercises)
        guard let match = blocks.first(where: { $0.id == blockID }) else {
            return nil
        }
        return WeekOverWeekProgress.ConditioningBlockSnapshot(
            label: match.name,
            detail: match.detail,
            date: result.date,
            repTimesSeconds: result.repTimesSeconds ?? [],
            durationSeconds: result.durationSeconds
        )
    }
}
