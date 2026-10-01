//
// TrainingViewModel+Pain.swift
// Tempo
//
// "This hurts" flow (pause/travel-pain feature). New file — see
// `PainReport.swift` (model + severity tiers) and `PainReportSheet.swift`
// (UI). Response by tier (careful, non-medical tone — no diagnosis, see the
// UI copy in `PainReportSheet.swift`):
// - mild (<=3): reduce load 20% for this exercise TODAY.
// - moderate (4-6): athlete picks "pain-free swap" (same muscle, DIFFERENT
//   movement pattern — deliberately not `swapAlternatives`, which prefers the
//   SAME movement) or "skip".
// - severe (7+): stop the exercise, suggest ending the session.
//
// Deliberately does NOT touch `TrainingViewModel+NoteSignals.swift`'s
// existing free-text pain-keyword signal — see `PainReport.swift`'s header
// for why the two systems stay separate.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Fetch

    func fetchPainReports(modelContext: ModelContext) -> [PainReport] {
        (try? modelContext.fetch(FetchDescriptor<PainReport>())) ?? []
    }

    /// Caution chip data — the most recent still-in-window report for this
    /// exercise, or nil.
    func recentPainCaution(for exerciseID: UUID, modelContext: ModelContext, now: Date = Date()) -> PainReport? {
        PainCaution.recentReport(for: exerciseID, in: fetchPainReports(modelContext: modelContext), asOf: now)
    }

    // MARK: - File a report + apply the tier response

    /// Files the report and applies the tier-appropriate automatic action
    /// (mild only — moderate/severe need the athlete's own follow-up choice,
    /// `applyPainSwap`/`skipExerciseDueToPain`, since "offer a swap or skip"
    /// isn't Tempo's call to make alone). Returns the filed report so the
    /// sheet can immediately reflect what happened.
    @discardableResult
    func filePainReport(
        plannedExercise: PlannedExercise?,
        bodyArea: PainBodyArea,
        severity: Int,
        note: String? = nil,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> PainReport {
        let tier = PainSeverityTier(severity: severity)
        let action: PainActionTaken = tier == .mild ? .reducedLoad : .none
        let report = PainReport(
            date: now,
            bodyArea: bodyArea,
            severity: severity,
            exerciseID: plannedExercise?.exercise?.id,
            exerciseNameSnapshot: plannedExercise?.displayName,
            actionTaken: action,
            note: note,
            createdAt: now
        )
        modelContext.insert(report)

        if tier == .mild, let plannedExercise {
            reduceLoad(for: plannedExercise, by: 0.8, modelContext: modelContext)
        }

        _ = modelContext.saveOrAlert("file pain report")
        HapticManager.selection()
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        return report
    }

    /// Mild — cut the target weight of every remaining, not-yet-completed
    /// working set on this exercise TODAY by `factor` (0.8 = 20% down),
    /// snapped to a loadable weight. Warm-ups scale off the SAME reduced
    /// working target so the ramp still makes sense. Mirrors `useTrainerWeight`
    /// /`propagateCalibration`'s exact "remaining, not-completed sets only"
    /// discipline — never rewrites a set that's already logged.
    private func reduceLoad(for plannedExercise: PlannedExercise, by factor: Double, modelContext: ModelContext) {
        guard let exercise = plannedExercise.exercise,
              let plan = plannedExercise.workoutPlan,
              plan.status == .planned || plan.status == .inProgress
        else {
            return
        }
        let unit = currentWeightUnit(modelContext: modelContext)
        let workingSets = plannedExercise.orderedSets.filter { !$0.isWarmup && !$0.completed }
        guard !workingSets.isEmpty else {
            return
        }
        for set in workingSets {
            let base = set.targetWeight ?? 0
            guard base > 0 else {
                continue
            }
            set.targetWeight = WeightConverter.loadableKg(base * factor, equipment: exercise.equipment, unit: unit)
        }
        for warmup in plannedExercise.orderedSets.filter({ $0.isWarmup && !$0.completed }) {
            guard let base = warmup.targetWeight, base > 0 else {
                continue
            }
            warmup.targetWeight = WeightConverter.loadableKg(base * factor, equipment: exercise.equipment, unit: unit)
        }
        plannedExercise.loadAdjustmentNote = "Pain note — reduced 20%"
        plannedExercise.painLoadReduced = true
    }

    // MARK: - Moderate: swap or skip

    /// Moderate-severity "pain-free swap": same MUSCLE group, a DIFFERENT
    /// movement pattern (unlike `swapAlternatives`, which prefers the SAME
    /// pattern — here the whole point is to change the movement that hurt).
    /// Excludes anything with an unresolved pain report in the last 7 days,
    /// same safety rule `swapAlternatives` already applies.
    func painFreeSwapAlternatives(for plannedExercise: PlannedExercise, modelContext: ModelContext) -> [Exercise] {
        guard let current = plannedExercise.exercise, let plan = plannedExercise.workoutPlan else {
            return []
        }
        let inPlan = Set(plan.orderedExercises.compactMap { $0.exercise?.id })
        let cutoff = Calendar.current.date(byAdding: .day, value: -PainCaution.windowDays, to: Date()) ?? .distantPast
        let cautioned = Set(
            fetchPainReports(modelContext: modelContext)
                .filter { $0.date >= cutoff }
                .compactMap(\.exerciseID)
        )
        let all = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        return all
            .filter {
                $0.muscleGroup == current.muscleGroup
                    && $0.movementPatternRaw != current.movementPatternRaw
                    && !inPlan.contains($0.id)
                    && !cautioned.contains($0.id)
            }
            .sorted { $0.name < $1.name }
    }

    /// Applies the chosen pain-free swap via the existing, already-tested
    /// `swapExercise` primitive, then tags the matching `PainReport` so the
    /// trainer report shows the outcome. Returns false when `swapExercise`
    /// refused (its own guard: a set on this exercise is already logged —
    /// exactly the likely case for a mid-exercise "This hurts" report). The
    /// report is deliberately left untouched (`actionTaken` stays `.none`) on
    /// failure so the caller can fall back to offering only "skip" instead of
    /// claiming a swap that never happened.
    @discardableResult
    func applyPainSwap(
        _ report: PainReport,
        plannedExercise: PlannedExercise,
        to newExercise: Exercise,
        modelContext: ModelContext
    ) -> Bool {
        guard swapExercise(plannedExercise, with: newExercise, modelContext: modelContext) else {
            return false
        }
        report.actionTaken = .swapped
        _ = modelContext.saveOrAlert("apply pain-free swap")
        return true
    }

    /// Moderate or severe — skip the exercise outright for today (see
    /// `PlannedExercise.painSkipped`). If the live session is sitting on it,
    /// move on to the next real work right away; the watch drops it too.
    func skipExerciseDueToPain(_ report: PainReport, plannedExercise: PlannedExercise, modelContext: ModelContext) {
        plannedExercise.painSkipped = true
        report.actionTaken = .skipped
        _ = modelContext.saveOrAlert("skip exercise for pain")
        if let plan = todayPlan,
           let index = plan.orderedExercises.firstIndex(where: { $0 === plannedExercise }),
           index == currentExerciseIndex
        {
            switch sessionState {
            case .warmup, .exercise(.setActive):
                advanceAfterSkip(in: plannedExercise, plan: plan, modelContext: modelContext)
            default:
                // Resting / between exercises: the rest end re-resolves the
                // cursor and already walks past a skipped exercise.
                break
            }
        }
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        pushWorkoutToWatch()
    }

    /// Whether the pain sheet can offer "End the session": only while a
    /// session is actually running (live, paused or on a call). From Today's
    /// list there is nothing to end.
    var canEndSessionForPain: Bool {
        switch sessionState {
        case .warmup, .exercise, .cooldown, .paused, .interruptedCall: true
        default: false
        }
    }

    /// Severe — the athlete confirmed ending the session from the pain sheet.
    /// Really ends it (it used to only record the choice and close the screen,
    /// leaving the session running in the background):
    /// - sets logged → finish normally, so they're saved to history and the
    ///   summary shows;
    /// - nothing logged → close the session and resolve the day as a
    ///   body-said-no skip (`.floorForced`), which doesn't count against
    ///   adherence.
    func endSessionDueToPain(
        _ report: PainReport,
        plannedExercise: PlannedExercise? = nil,
        modelContext: ModelContext
    ) {
        // Mark the hurting exercise skipped WITHOUT advancing — ending is the
        // next step, not moving on to the next lift.
        plannedExercise?.painSkipped = true
        report.actionTaken = .endedSession
        _ = modelContext.saveOrAlert("end session for pain")
        guard canEndSessionForPain else { return }
        if hasAnyCompletedWorkingSet {
            finishWorkout(modelContext: modelContext)
            return
        }
        guard let plan = todayPlan else { return }
        discardActiveWorkout(modelContext: modelContext)
        // The discard's rollback hands every lift back for a redo — except the
        // one that hurt: it stays flagged so "Train anyway" doesn't bring it
        // back unmarked.
        plannedExercise?.painSkipped = true
        plan.status = .skipped
        plan.skipReason = .floorForced
        saveGuarded(modelContext, operation: "pain-ended workout")
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
    }
}
