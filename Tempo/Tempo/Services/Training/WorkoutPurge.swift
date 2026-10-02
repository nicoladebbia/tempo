//
// WorkoutPurge.swift
// Tempo
//
// Deleting a workout from History removes the session AND every record it
// produced, so it disappears from history, weekly volume, progress charts,
// PRs and the coach's day alike. Pulled out of WorkoutHistoryView so the
// rules are unit-testable. What it deliberately keeps: the engine's learned
// adjustments (AdaptiveProfile / learned increments) — they are averaged
// over many sessions and can't be un-learned per session; the delete
// confirmation says so.
//

import Foundation
import SwiftData

enum WorkoutPurge {
    /// Which `ExerciseHistory` rows deleting `workout` should also remove.
    /// Matched by `workoutPlanID` FIRST — the exact key completion stamps on
    /// every row it writes. A row with no `workoutPlanID` (legacy, written
    /// before the stamp existed) falls back to the old day + exercise match,
    /// which, used alone, could delete the OTHER same-day workout's row for a
    /// shared exercise (§13).
    static func historyRowsToDelete(
        for workout: WorkoutPlan,
        allHistory: [ExerciseHistory],
        calendar: Calendar = .current
    ) -> [ExerciseHistory] {
        let sessionDay = calendar.startOfDay(for: workout.finishedAt ?? workout.date)
        let exerciseIDs = Set(workout.orderedExercises.compactMap { $0.exercise?.id })
        return allHistory.filter { h in
            if let hPlanID = h.workoutPlanID {
                return hPlanID == workout.id
            }
            return calendar.isDate(h.date, inSameDayAs: sessionDay)
                && (h.exercise?.id).map(exerciseIDs.contains) == true
        }
    }

    /// The coach's DailySession rows that belong to `workout`: by stamped id;
    /// a legacy (unstamped) row only by day, and only when no OTHER workout
    /// shares that day — otherwise we can't tell whose it is and keep it.
    static func dailySessionsToDelete(
        for workout: WorkoutPlan,
        allSessions: [DailySession],
        allPlans: [WorkoutPlan],
        calendar: Calendar = .current
    ) -> [DailySession] {
        let day = calendar.startOfDay(for: workout.date)
        let dayHasOtherPlan = allPlans.contains {
            $0.id != workout.id && calendar.isDate($0.date, inSameDayAs: day)
        }
        return allSessions.filter { s in
            if let planID = s.workoutPlanID {
                return planID == workout.id
            }
            return !dayHasOtherPlan && calendar.isDate(s.date, inSameDayAs: day)
        }
    }

    /// The "This hurts" reports deleting `workout` should also remove, so a pain
    /// flag it produced doesn't outlive it. Matched by the stamped plan id; a
    /// legacy (unstamped) report only when it names one of this workout's lifts
    /// on its day and no OTHER workout that day trained the same lift. A report
    /// another remaining workout filed is never touched.
    static func painReportsToDelete(
        for workout: WorkoutPlan,
        allReports: [PainReport],
        allPlans: [WorkoutPlan],
        calendar: Calendar = .current
    ) -> [PainReport] {
        let day = calendar.startOfDay(for: workout.finishedAt ?? workout.date)
        let exerciseIDs = Set(workout.orderedExercises.compactMap { $0.exercise?.id })
        let otherIDsThatDay = Set(
            allPlans
                .filter { $0.id != workout.id && calendar.isDate($0.finishedAt ?? $0.date, inSameDayAs: day) }
                .flatMap(\.orderedExercises)
                .compactMap { $0.exercise?.id }
        )
        return allReports.filter { r in
            if let planID = r.workoutPlanID {
                return planID == workout.id
            }
            guard let exID = r.exerciseID else {
                return false
            }
            return exerciseIDs.contains(exID)
                && !otherIDsThatDay.contains(exID)
                && calendar.isDate(r.date, inSameDayAs: day)
        }
    }

    /// Hard delete. WorkoutPlan cascades to PlannedExercise → PlannedSet;
    /// everything else that points at the session by id is removed here.
    /// Saves, then tells every surface (Today, Dashboard, watch, day plan).
    @MainActor
    @discardableResult
    static func purge(_ workout: WorkoutPlan, modelContext: ModelContext) -> Bool {
        let planID = workout.id
        let setIDs = Set(workout.orderedExercises.flatMap { ($0.sets ?? []).map(\.id) })

        // 1. Set feedback (links to PlannedSet with .nullify — would orphan).
        for fb in fetch(SetFeedback.self, modelContext) where setIDs.contains(fb.setID) {
            modelContext.delete(fb)
        }
        // 2. ExerciseHistory rows this session created.
        for h in historyRowsToDelete(for: workout, allHistory: fetch(ExerciseHistory.self, modelContext)) {
            modelContext.delete(h)
        }
        // 3. PRs, prediction logs, non-gym ActivitySessions and conditioning
        //    block results stamped with this plan.
        for pr in fetch(PersonalRecord.self, modelContext) where pr.workoutPlanID == planID {
            modelContext.delete(pr)
        }
        for log in fetch(PredictionLog.self, modelContext) where log.workoutPlanID == planID {
            modelContext.delete(log)
        }
        for session in fetch(ActivitySession.self, modelContext) where session.workoutPlanID == planID {
            modelContext.delete(session)
        }
        for result in fetch(ConditioningBlockResult.self, modelContext) where result.workoutPlanID == planID {
            modelContext.delete(result)
        }
        // 4. The coach's session for this workout (a dangling one-way link
        //    would later crash sessionRPEAccuracy).
        let sessions = dailySessionsToDelete(
            for: workout,
            allSessions: fetch(DailySession.self, modelContext),
            allPlans: fetch(WorkoutPlan.self, modelContext)
        )
        for s in sessions {
            modelContext.delete(s)
        }
        // A legacy session kept because the day is ambiguous must not keep
        // pointing at the deleted plan (one-way link → dangling reference).
        let deletedIDs = Set(sessions.map(\.persistentModelID))
        for s in fetch(DailySession.self, modelContext)
            where !deletedIDs.contains(s.persistentModelID)
            && s.workoutPlanID == nil
            && s.workoutPlan?.persistentModelID == workout.persistentModelID {
            s.workoutPlan = nil
        }
        // 4b. Pain reports filed in this session (the "Pain flagged" chip).
        for r in painReportsToDelete(
            for: workout,
            allReports: fetch(PainReport.self, modelContext),
            allPlans: fetch(WorkoutPlan.self, modelContext)
        ) {
            modelContext.delete(r)
        }
        // 5. The plan itself.
        modelContext.delete(workout)
        guard modelContext.saveOrAlert("history change") else {
            return false
        }
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        NotificationCenter.default.post(
            name: .tempoDayPlanReplanRequested,
            object: nil,
            userInfo: ["reason": DayPlanReason.workoutLogged.rawValue]
        )
        return true
    }

    private static func fetch<T: PersistentModel>(_: T.Type, _ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}
