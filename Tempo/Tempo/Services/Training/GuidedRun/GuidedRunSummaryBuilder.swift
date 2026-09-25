//
// GuidedRunSummaryBuilder.swift
// Tempo
//
// Guided run mode — maps a finished session's per-block records onto the
// EXISTING `TrainingViewModel.logConditioningBlock` call, one call per
// block, so History/trainer report/completion/Dashboard Move/Week Plan all
// update through the paths they already use (no parallel completion flag —
// see TrainingViewModel+ConditioningLogging.swift's header). Pure — the
// summary view calls this to get the parameters, then calls
// `logConditioningBlock` itself (which needs a live `ModelContext`).
//

import Foundation

enum GuidedRunSummaryBuilder {
    struct BlockLogInput: Equatable {
        let blockID: UUID
        let detail: String?
        let repTimesSeconds: [Double]?
        let durationSeconds: Double?
        let distanceMeters: Double?
        let roundsCompleted: Int?
        let rpe: Double?
        let notes: String?
    }

    /// One input per block that has ANY recorded result (a block skipped in
    /// full — never started — is left out; there's nothing to log). RPE and
    /// notes are per SESSION on the summary screen (one picker, one field)
    /// and are attached to every logged block, matching how a single
    /// `ConditioningLogSheet` submission already pairs one RPE/notes with
    /// one block.
    static func blockInputs(
        plan: GuidedRunPlan,
        results: [UUID: GuidedRunBlockRecord],
        rpe: Double?,
        notes: String?
    ) -> [BlockLogInput] {
        plan.blocks.compactMap { block in
            guard let record = results[block.id], hasAnyResult(record) else {
                return nil
            }
            return BlockLogInput(
                blockID: block.id,
                detail: block.rawDetail,
                repTimesSeconds: record.repTimesSeconds.isEmpty ? nil : record.repTimesSeconds,
                durationSeconds: record.durationSeconds,
                distanceMeters: record.distanceMeters,
                roundsCompleted: record.roundsCompleted > 0 ? record.roundsCompleted : nil,
                rpe: rpe,
                notes: notes
            )
        }
    }

    private static func hasAnyResult(_ record: GuidedRunBlockRecord) -> Bool {
        !record.repTimesSeconds.isEmpty
            || record.roundsCompleted > 0
            || record.durationSeconds != nil
            || record.distanceMeters != nil
    }
}
