//
// TrainerScheduleOverrides.swift
// Tempo
//
// The days on which Tempo itself deliberately overrides a trainer's fixed
// session: a paused day (sick / injured / travel), a match day, or a day red
// recovery benched to mobility. Not a miss on the athlete's part — shared by
// the "missed session" prompt (`missedFixedSession`) and the compliance
// stats (`TrainerProgramHistoryStats`) so the two always agree.
//

import Foundation
import SwiftData

struct TrainerScheduleOverrides {
    var pauses: [TrainingPause] = []
    /// Start-of-day keys of match days.
    var matchDays: Set<Date> = []

    /// Pauses and matches fetched from the store (all of them, past included).
    @MainActor
    static func fetch(modelContext: ModelContext) -> TrainerScheduleOverrides {
        let pauses = (try? modelContext.fetch(FetchDescriptor<TrainingPause>())) ?? []
        let matches = (try? modelContext.fetch(FetchDescriptor<Match>())) ?? []
        let cal = Calendar.current
        return TrainerScheduleOverrides(pauses: pauses, matchDays: Set(matches.map { cal.startOfDay(for: $0.kickoff) }))
    }

    /// True when `date` was paused, a match day, or benched by red recovery
    /// (`persisted` = the plan row stored for that day, if any).
    func overrides(_ date: Date, persisted: WorkoutPlan?, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        if matchDays.contains(day) {
            return true
        }
        if TrainingPauseSchedule.coveringPause(pauses, on: day, calendar: calendar) != nil {
            return true
        }
        return persisted.map(Self.isRedRecoveryBench) ?? false
    }

    /// Red recovery turned the day into mobility: recovery adjustment 0, no
    /// trainer session left on it.
    static func isRedRecoveryBench(_ plan: WorkoutPlan) -> Bool {
        plan.recoveryAdjustment == 0 && plan.type == .mobility && plan.programSessionKey == nil
    }
}
