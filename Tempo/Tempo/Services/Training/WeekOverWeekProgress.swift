//
// WeekOverWeekProgress.swift
// Tempo
//
// Sunday wrap-up / trainer-report feature — pure week-over-week comparison.
// For each exercise done in the reporting window, finds the most recent
// EARLIER session of the SAME exercise (`Exercise.id`, via
// `ExerciseHistory.exercise`) — regardless of which weekly `TrainerProgram`
// either session belonged to. A new program lands every week (see
// `TrainerProgramWeeklyUpload`), so an exercise's identity never depends on
// which program's `ProgramExercise` row happened to reference it; only
// `Exercise.id` does.
//
// Conditioning blocks work the same way but CAN'T be matched by ID: every
// weekly upload mints fresh `ProgramExercise.id`s (`blockID` on
// `ConditioningBlockResult`), so a block's identity across weeks is its
// trainer-written NAME, or — when that's missing — its parsed
// `ConditioningTargetParser` SHAPE (same reps × distance × cap, etc.).
//
// Pure and side-effect free, same convention as `TrainerReportBuilder`:
// callers (`WeekOverWeekProgressLoader`, the Sunday wrap-up recap) fetch the
// SwiftData rows and hand them in plainly. `ExerciseHistory`/
// `ConditioningBlockResult` are read here as plain data, never mutated.
//

import Foundation

// MARK: - WeekOverWeekProgress

enum WeekOverWeekProgress {
    // MARK: - Exercise comparison

    struct ExerciseDelta: Identifiable, Equatable, Sendable {
        var exerciseID: UUID
        var id: UUID {
            exerciseID
        }

        var name: String
        var currentDate: Date
        var previousDate: Date
        var currentBestWeightKg: Double?
        var currentBestReps: Int?
        var previousBestWeightKg: Double?
        var previousBestReps: Int?
        /// current − previous; nil when either session has no e1RM.
        var e1RMDelta: Double?
        /// current − previous total logged volume for this exercise.
        var volumeDelta: Double?
    }

    /// One row per exercise that appears in `currentHistories` AND has an
    /// earlier row in `priorHistories` for the SAME `Exercise` — an exercise
    /// done for the first time ever has nothing to compare against and is
    /// left out entirely (not a zero-delta row). When an exercise was logged
    /// more than once within the current window (a two-a-day, a repeated
    /// block), the MOST RECENT occurrence in the window is "current" —
    /// comparisons always look forward from the week's freshest number, and
    /// the MOST RECENT occurrence in `priorHistories` is "previous".
    ///
    /// Contract: `priorHistories` must already be everything strictly BEFORE
    /// the current window (the caller's own fetch boundary — see
    /// `WeekOverWeekProgressLoader`) — this never re-checks dates against
    /// `currentHistories` itself, so passing overlapping rows would corrupt
    /// the "previous" pick.
    static func compareExercises(
        currentHistories: [ExerciseHistory],
        priorHistories: [ExerciseHistory]
    ) -> [ExerciseDelta] {
        let priorByExercise = latestByKey(priorHistories) { $0.exercise?.id }
        let currentByExercise = latestByKey(currentHistories) { $0.exercise?.id }

        return currentByExercise.compactMap { exerciseID, current -> ExerciseDelta? in
            guard let previous = priorByExercise[exerciseID] else {
                return nil
            }
            return ExerciseDelta(
                exerciseID: exerciseID,
                name: current.displayName,
                currentDate: current.date,
                previousDate: previous.date,
                currentBestWeightKg: current.bestSetWeight,
                currentBestReps: current.bestSetReps,
                previousBestWeightKg: previous.bestSetWeight,
                previousBestReps: previous.bestSetReps,
                e1RMDelta: delta(current.estimated1RM, previous.estimated1RM),
                volumeDelta: current.totalVolume - previous.totalVolume
            )
        }
        .sorted { $0.currentDate < $1.currentDate }
    }

    // MARK: - Conditioning comparison

    /// Plain snapshot of one logged conditioning block, already resolved back
    /// to its trainer-written label/prescription text — see
    /// `WeekOverWeekProgressLoader.snapshot(for:programsByID:)`.
    struct ConditioningBlockSnapshot {
        var label: String
        var detail: String?
        var date: Date
        var repTimesSeconds: [Double]
        var durationSeconds: Double?

        var avgSeconds: Double? {
            if !repTimesSeconds.isEmpty {
                return repTimesSeconds.reduce(0, +) / Double(repTimesSeconds.count)
            }
            return durationSeconds
        }

        var bestSeconds: Double? {
            if !repTimesSeconds.isEmpty {
                return repTimesSeconds.min()
            }
            return durationSeconds
        }
    }

    struct ConditioningDelta: Identifiable, Equatable, Sendable {
        var matchKey: String
        var id: String {
            matchKey
        }

        var blockLabel: String
        var currentDate: Date
        var previousDate: Date
        var currentAvgSeconds: Double?
        var currentBestSeconds: Double?
        var previousAvgSeconds: Double?
        var previousBestSeconds: Double?
    }

    /// Same "most recent current vs most recent prior" rule as
    /// `compareExercises`, keyed by `matchKey(for:)` instead of an ID.
    static func compareConditioning(
        currentBlocks: [ConditioningBlockSnapshot],
        priorBlocks: [ConditioningBlockSnapshot]
    ) -> [ConditioningDelta] {
        let priorByKey = latestByKey(priorBlocks) { matchKey(for: $0) }
        let currentByKey = latestByKey(currentBlocks) { matchKey(for: $0) }

        return currentByKey.compactMap { key, current -> ConditioningDelta? in
            guard let previous = priorByKey[key] else {
                return nil
            }
            return ConditioningDelta(
                matchKey: key,
                blockLabel: current.label,
                currentDate: current.date,
                previousDate: previous.date,
                currentAvgSeconds: current.avgSeconds,
                currentBestSeconds: current.bestSeconds,
                previousAvgSeconds: previous.avgSeconds,
                previousBestSeconds: previous.bestSeconds
            )
        }
        .sorted { $0.currentDate < $1.currentDate }
    }

    /// Name match first (trimmed/lowercased label — stable across weeks even
    /// though every re-upload mints a fresh `ProgramExercise.id`); falls back
    /// to the parsed prescription SHAPE when the label is empty, so a
    /// renamed-but-identical block ("Shuttle 1" → "Shuttle A", same reps ×
    /// distance × cap) still matches.
    static func matchKey(for block: ConditioningBlockSnapshot) -> String {
        let normalizedName = block.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalizedName.isEmpty {
            return "name:\(normalizedName)"
        }
        return "shape:\(shapeSignature(ConditioningTargetParser.parse(detail: block.detail).kind))"
    }

    /// Same key a report row's plain `blockLabel` text can reproduce — used
    /// by `Result.conditioningDelta(forBlockLabel:)` to look a delta back up
    /// once all it has is the display label, not the original snapshot.
    static func matchKey(forLabel label: String) -> String {
        "name:\(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func shapeSignature(_ kind: ConditioningTargetKind) -> String {
        switch kind {
        case let .repsDistance(reps, distance, unit, cap):
            "repsDistance-\(reps)-\(distance)-\(unit.rawValue)-\(cap ?? -1)"
        case let .duration(minutes):
            "duration-\(minutes)"
        case let .intervalSets(sets, reps):
            "intervalSets-\(sets)-\(reps)"
        case let .distance(value, unit):
            "distance-\(value)-\(unit.rawValue)"
        case .freeform:
            "freeform"
        }
    }

    // MARK: - Shared helpers

    /// Groups `items` by `key`, keeping only the most recent (by `date`) per
    /// key — the "latest occurrence wins" rule both comparisons share.
    private static func latestByKey<T: DatedItem, Key: Hashable>(
        _ items: [T],
        key: (T) -> Key?
    ) -> [Key: T] {
        var result: [Key: T] = [:]
        for item in items {
            guard let itemKey = key(item) else {
                continue
            }
            if let existing = result[itemKey], existing.date >= item.date {
                continue
            }
            result[itemKey] = item
        }
        return result
    }

    private static func delta(_ current: Double?, _ previous: Double?) -> Double? {
        guard let current, let previous else {
            return nil
        }
        return current - previous
    }
}

// MARK: - DatedItem

/// Lets `latestByKey` work generically over both `ExerciseHistory` (a
/// SwiftData model) and `ConditioningBlockSnapshot` (a plain struct).
private protocol DatedItem {
    var date: Date { get }
}

// MARK: - ExerciseHistory + DatedItem

extension ExerciseHistory: DatedItem {}

// MARK: - WeekOverWeekProgress.ConditioningBlockSnapshot + DatedItem

extension WeekOverWeekProgress.ConditioningBlockSnapshot: DatedItem {}

// MARK: - WeekOverWeekProgress.Result

extension WeekOverWeekProgress {
    /// Bundles both comparisons for one reporting window — what
    /// `WeekOverWeekProgressLoader` hands to the wrap-up recap and to
    /// `TrainerReportInput.weekOverWeek`.
    struct Result: Sendable {
        var exercises: [ExerciseDelta] = []
        var conditioning: [ConditioningDelta] = []

        static let empty = Result()

        func exerciseDelta(forExerciseID exerciseID: UUID) -> ExerciseDelta? {
            exercises.first { $0.exerciseID == exerciseID }
        }

        func conditioningDelta(forBlockLabel blockLabel: String) -> ConditioningDelta? {
            let key = WeekOverWeekProgress.matchKey(forLabel: blockLabel)
            return conditioning.first { $0.matchKey == key }
        }
    }
}

// MARK: - Display formatting

extension WeekOverWeekProgress.ExerciseDelta {
    private static func formatKg(_ kg: Double) -> String {
        kg == kg.rounded() ? "\(Int(kg))" : String(format: "%.1f", kg)
    }

    /// "60→65 kg (+5)" — best-set weight change plus the e1RM delta, when
    /// both sessions have one. Falls back to just the current best when
    /// there's no weight to diff (e.g. only reps changed).
    var weightChangeText: String? {
        guard let currentWeight = currentBestWeightKg else {
            return nil
        }
        var text = if let previousWeight = previousBestWeightKg, previousWeight != currentWeight {
            "\(Self.formatKg(previousWeight))→\(Self.formatKg(currentWeight)) kg"
        } else {
            "\(Self.formatKg(currentWeight)) kg"
        }
        if let e1RMDelta, abs(e1RMDelta) >= 0.5 {
            let sign = e1RMDelta > 0 ? "+" : ""
            text += " (\(sign)\(Self.formatKg(e1RMDelta)))"
        }
        return text
    }

    /// "RDL 60→65 kg (+5)" — the wrap-up recap's bullet format.
    var recapLine: String {
        guard let change = weightChangeText else {
            return name
        }
        return "\(name) \(change)"
    }
}

extension WeekOverWeekProgress.ConditioningDelta {
    private static func formatSeconds(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        return minutes > 0 ? String(format: "%d:%02d", minutes, secs) : "\(secs)″"
    }

    /// "avg 61″→58″" — nil when neither session logged a time-based metric
    /// (e.g. both were distance-only).
    var avgChangeText: String? {
        guard let current = currentAvgSeconds, let previous = previousAvgSeconds else {
            return nil
        }
        return "avg \(Self.formatSeconds(previous))→\(Self.formatSeconds(current))"
    }

    /// "Shuttle avg 61″→58″" — the wrap-up recap's bullet format.
    var recapLine: String {
        guard let change = avgChangeText else {
            return blockLabel
        }
        return "\(blockLabel) \(change)"
    }
}
