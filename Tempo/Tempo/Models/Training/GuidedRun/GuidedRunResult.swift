//
// GuidedRunResult.swift
// Tempo
//
// Guided run mode — what actually happened, accumulated live by
// `GuidedRunSession` as the athlete works through a block, and later mapped
// 1:1 onto `TrainingViewModel.logConditioningBlock`'s parameters (same
// fields `ConditioningBlockResult` stores) by `GuidedRunSummaryBuilder`.
//

import Foundation

// MARK: - GuidedRunBlockRecord

/// Live/final record for one block (`GuidedRunBlock.id` / `ProgramExercise
/// .id`). Every field mirrors a `ConditioningBlockResult` column so the
/// summary screen can hand this straight to `logConditioningBlock`.
struct GuidedRunBlockRecord: Equatable {
    let blockID: UUID
    var repTimesSeconds: [Double] = []
    var roundsCompleted: Int = 0
    var durationSeconds: Double?
    var distanceMeters: Double?
    /// Reps/rounds skipped rather than performed — not logged as a time,
    /// but shown on the summary so the athlete sees what was cut.
    var skippedCount: Int = 0

    /// Apple Watch run mode — every live BPM sample streamed in while this
    /// block's steps were active (`GuidedRunSession.updateLiveHeartRate`).
    /// Empty with no paired/reachable Watch — the summary and
    /// `ConditioningBlockResult` just show nothing HR-related.
    var heartRateSamplesBPM: [Double] = []

    var avgHeartRateBPM: Double? {
        guard !heartRateSamplesBPM.isEmpty else {
            return nil
        }
        return heartRateSamplesBPM.reduce(0, +) / Double(heartRateSamplesBPM.count)
    }

    var maxHeartRateBPM: Double? {
        heartRateSamplesBPM.max()
    }

    /// Live ✓/✗ per timed rep against `capSeconds`, in rep order — nil
    /// entries are reps with no cap to judge against.
    func repChecks(capSeconds: Double?) -> [Bool?] {
        guard let capSeconds else {
            return repTimesSeconds.map { _ in nil }
        }
        return repTimesSeconds.map { time -> Bool? in time <= capSeconds }
    }

    var bestRepSeconds: Double? {
        ConditioningTargetEvaluator.bestTime(repTimesSeconds)
    }

    var averageRepSeconds: Double? {
        guard !repTimesSeconds.isEmpty else {
            return nil
        }
        return repTimesSeconds.reduce(0, +) / Double(repTimesSeconds.count)
    }
}

// MARK: - GuidedRunCue

/// A cue the engine wants played — the session itself never touches
/// AVFoundation/UIKit; a `GuidedRunCueService` (or the fake spy in tests)
/// subscribes via `GuidedRunSession.cueHandler`.
enum GuidedRunCue: Equatable {
    case countdown(Int) // 3, 2, 1
    case go
    case restStart
    case tenSecondsLeft
    case halfway
    case done
    /// Entering a new timed rep — "Rep 2 of 4, cap 65" / "Last rep, cap 65".
    /// `index`/`of` are 0-based-in / 1-based-total, matching `GuidedRunTimedRep`.
    case repStart(index: Int, of: Int, capSeconds: Double?, isLast: Bool)
    /// A timed rep just completed — under/over its cap (nil cap: just the time).
    case repResult(elapsedSeconds: Double, capSeconds: Double?)
}
