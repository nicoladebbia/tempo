//
// TrainingViewModel+DailyCoachOverrides.swift
// Tempo
//
// The athlete's side of the daily coach's decisions: decline the brain's
// modality move (`keepPlannedWorkout`), train on a day benched for recovery
// (`trainAnyway`), and tick off the cardio second session of a two-a-day
// (`toggleSecondarySessionComplete`). Moved out of TrainingViewModel.swift to
// keep that file under the lint length limit; behaviour is unchanged.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Keep Planned Workout (§8 connect — the user's side of the seam)

    /// Decline the brain's modality move and restore the planned day ("coach
    /// said rest, I'm swimming anyway"). Only a brain-CHOSEN move is
    /// declinable — a SEVERE floor skip never stashes plannedTypeRaw, so this
    /// is a no-op there by construction. The session is marked overridden so
    /// the card collapses and nothing re-applies the move today.
    func keepPlannedWorkout(modelContext: ModelContext) {
        guard let plan = todayPlan,
              plan.status == .planned,
              let stashed = plan.plannedTypeRaw
        else {
            return
        }
        plan.typeRaw = stashed
        plan.plannedTypeRaw = nil
        dailySession?.userOverrode = true
        saveGuarded(modelContext, operation: "workout choice")
        // Watch + Dashboard read the persisted plan directly — without this
        // they keep showing the coach's move until their next unrelated reload.
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        #if DEBUG
            print("\(DebugTrace.prefix)[daily_coach] user kept planned workout → \(stashed)")
        #endif
    }

    /// The day was benched for the body (severe readiness or pain →
    /// `.skipped` + `.floorForced`) and the athlete wants to train anyway.
    /// Reopens the plan and marks today's coach session overridden so the
    /// next readiness pass doesn't bench it again. A user skip is not
    /// reopened here — that was their own call.
    func trainAnyway(modelContext: ModelContext) {
        guard let plan = todayPlan,
              plan.status == .skipped,
              plan.skipReason == .floorForced
        else {
            return
        }
        plan.status = .planned
        plan.skipReason = nil
        dailySession?.userOverrode = true
        saveGuarded(modelContext, operation: "train anyway")
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
    }

    /// Whether today is benched for recovery and can be reopened.
    var isRecoveryBenched: Bool {
        todayPlan?.status == .skipped && todayPlan?.skipReason == .floorForced
    }

    /// §21 (b) — check off (or undo) the cardio SECOND session of a gym+cardio
    /// two-a-day. The lift's completion rides `status` (the DAY counts as trained
    /// on the lift), so this flag tracks the bonus cardio INDEPENDENTLY — it never
    /// gates the day. No-op on a single-session day.
    ///
    /// Marking it done LOGS the cardio as a manual `ActivitySession` — the same
    /// record a standalone cross-training day writes (persistNonGymCompletion) —
    /// so the bonus session feeds the real intelligence: the §14 (d) modality
    /// learner (doing the two-a-day cardio reinforces the learned preference),
    /// venue patterns, and the load/replan cascade. Undo removes that row, so the
    /// flag and the logged activity never disagree.
    func toggleSecondarySessionComplete(modelContext: ModelContext) {
        guard let plan = todayPlan, plan.isTwoADay, let second = plan.secondarySessionType else {
            return
        }
        plan.secondaryCompleted.toggle()

        let planID = plan.id
        let typeRaw = second.rawValue
        // The cardio's own ActivitySession, keyed (planID, type) so it's found on
        // undo. The gym lift writes ExerciseHistory (not ActivitySession), so this
        // is the ONLY ActivitySession for the plan — no collision with the lift.
        let existing = (try? modelContext.fetch(FetchDescriptor<ActivitySession>(
            predicate: #Predicate<ActivitySession> { $0.workoutPlanID == planID && $0.workoutType == typeRaw }
        ))) ?? []
        for row in existing {
            modelContext.delete(row)
        } // dedup / undo both start clean

        if plan.secondaryCompleted {
            let cardio = ActivitySession(
                date: Date(), startTime: Date(), workoutType: typeRaw, sportID: -1,
                source: "manual", workoutPlanID: planID,
                strain: nil, averageHeartRate: nil, maxHeartRate: nil,
                caloriesBurned: nil, durationMinutes: 30
            )
            modelContext.insert(cardio)
        }
        saveGuarded(modelContext, operation: "second session")

        if plan.secondaryCompleted {
            // Same cross-surface signals as any non-gym completion — feeds venue
            // learning and lets the Move quadrant / recovery cascade react.
            VenuePatternLearner.recompute(modelContext: modelContext)
            NotificationCenter.default.post(
                name: .tempoDayPlanReplanRequested, object: nil,
                userInfo: ["reason": DayPlanReason.workoutLogged.rawValue]
            )
            NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        }
        #if DEBUG
            print(
                "\(DebugTrace.prefix)[daily_coach] two-a-day second session → \(plan.secondaryCompleted ? "done (logged \(typeRaw))" : "undone (removed)")"
            )
        #endif
    }
}
