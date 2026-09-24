//
// TrainingViewModel+ConditioningLogging.swift
// Tempo
//
// Fix #7 — recording how a trainer-program conditioning block actually went
// (shuttle times vs the trainer's cap, run duration/distance, drill rounds,
// effort). Logging a block persists a `ConditioningBlockResult` and, once at
// least one block of the day's session is logged, marks the session done
// through the EXISTING completion path for that case — never a parallel flag:
// - primary conditioning day (`plan.programSessionKey`) → the same
//   `persistNonGymCompletion` the "Log that I played" / Whoop-confirm flow
//   uses.
// - second session of a two-a-day (`plan.programSecondaryKey`) → the same
//   `toggleSecondarySessionComplete` the "Mark done" button uses.
// Readers of those two signals (Dashboard Move, Watch, History, Week Plan)
// are unchanged — they still just read `plan.status` / `plan.secondaryCompleted`.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Fill from Whoop/Health

    struct ConditioningFillData: Equatable {
        var durationMinutes: Double?
        var distanceMeters: Double?
        var averageHeartRate: Double?
        /// "whoop" | "healthkit"
        var source: String
    }

    /// Best-effort today's activity to prefill a block's duration/distance/HR
    /// from — tried Whoop first (matches the non-gym confirm flow's source of
    /// truth when connected to a real account), then HealthKit (has distance,
    /// which Whoop's workout payload doesn't carry). nil when neither has
    /// anything for today, or the day being logged isn't today.
    func conditioningFillData(for date: Date, modelContext: ModelContext) async -> ConditioningFillData? {
        guard Calendar.current.isDateInToday(date) else {
            return nil
        }

        if whoop.providesRealData, let activities = try? await whoop.fetchWorkouts(for: date) {
            let cal = Calendar.current
            let todays = activities.filter { cal.isDate($0.startTime, inSameDayAs: date) }
            if let best = todays.max(by: { $0.strain < $1.strain }) {
                return ConditioningFillData(
                    durationMinutes: best.durationMinutes,
                    distanceMeters: nil,
                    averageHeartRate: best.averageHeartRate,
                    source: "whoop"
                )
            }
        }

        if let workouts = try? await healthKit.fetchWorkouts(for: date) {
            let cal = Calendar.current
            let todays = workouts.filter { cal.isDate($0.startDate, inSameDayAs: date) }
            if let best = todays.max(by: { $0.durationMinutes < $1.durationMinutes }) {
                return ConditioningFillData(
                    durationMinutes: best.durationMinutes,
                    distanceMeters: best.distanceMeters,
                    averageHeartRate: best.averageHeartRate,
                    source: "healthkit"
                )
            }
        }

        return nil
    }

    // MARK: - Read

    /// Every logged result for a program session, most recently logged
    /// first — the card's compact summary and Workout History's grouping
    /// both read this by the same key the plan stamped
    /// (`programSessionKey` / `programSecondaryKey`).
    func conditioningResults(forSessionKey key: String?, modelContext: ModelContext) -> [ConditioningBlockResult] {
        guard let key, !key.isEmpty else {
            return []
        }
        let descriptor = FetchDescriptor<ConditioningBlockResult>(
            predicate: #Predicate<ConditioningBlockResult> { $0.programSessionKey == key },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Write

    /// Save (or replace) one block's result. Parses the block's own `detail`
    /// text into a target and evaluates target-met at save time, so the card
    /// and History never need the parser on hand to show a ✓/✗. Then bridges
    /// completion (see file header) — a no-op if the session is already
    /// marked done.
    @discardableResult
    func logConditioningBlock(
        workoutPlanID: UUID,
        programSessionKey: String,
        blockID: UUID,
        detail: String?,
        repTimesSeconds: [Double]?,
        durationSeconds: Double?,
        distanceMeters: Double?,
        roundsCompleted: Int?,
        rpe: Double?,
        notes: String?,
        source: String,
        modelContext: ModelContext
    ) -> ConditioningBlockResult {
        let target = ConditioningTargetParser.parse(detail: detail)
        let met = ConditioningTargetEvaluator.targetMet(
            target: target,
            repTimesSeconds: repTimesSeconds,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            roundsCompleted: roundsCompleted
        )

        // Replace any prior log for this exact block — re-logging edits the
        // result, it doesn't duplicate it. Same dedup convention as
        // persistNonGymCompletion's ActivitySession handling.
        let existing = (try? modelContext.fetch(FetchDescriptor<ConditioningBlockResult>(
            predicate: #Predicate<ConditioningBlockResult> {
                $0.blockID == blockID && $0.workoutPlanID == workoutPlanID
            }
        ))) ?? []
        for row in existing {
            modelContext.delete(row)
        }

        let result = ConditioningBlockResult(
            workoutPlanID: workoutPlanID,
            programSessionKey: programSessionKey,
            blockID: blockID,
            repTimesSeconds: repTimesSeconds,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            roundsCompleted: roundsCompleted,
            rpe: rpe,
            notes: notes,
            targetMet: met,
            source: source
        )
        modelContext.insert(result)
        saveGuarded(modelContext, operation: "conditioning block result")

        #if DEBUG
            print(
                "\(DebugTrace.prefix)[Workout] logConditioningBlock: plan=\(workoutPlanID) key=\(programSessionKey) block=\(blockID) targetMet=\(met.map(String.init) ?? "unknown")"
            )
        #endif

        bridgeCompletion(workoutPlanID: workoutPlanID, programSessionKey: programSessionKey, modelContext: modelContext)

        return result
    }

    /// Mark the day's conditioning session done through the EXISTING
    /// completion path, once at least one block has been logged. Only acts
    /// on TODAY'S plan (the only place `TrainerSessionCard` — and therefore
    /// logging — renders); a no-op otherwise, or if the plan/key no longer
    /// match (program re-imported since) or it's already completed.
    private func bridgeCompletion(workoutPlanID: UUID, programSessionKey: String, modelContext: ModelContext) {
        guard let plan = todayPlan, plan.id == workoutPlanID else {
            return
        }
        if plan.programSessionKey == programSessionKey {
            if plan.status != .completed {
                persistNonGymCompletion(whoop: nil, modelContext: modelContext)
            }
        } else if plan.programSecondaryKey == programSessionKey {
            if !plan.secondaryCompleted {
                toggleSecondarySessionComplete(modelContext: modelContext)
            }
        }
    }
}
