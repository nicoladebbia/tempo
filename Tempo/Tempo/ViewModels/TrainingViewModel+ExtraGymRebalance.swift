//
// TrainingViewModel+ExtraGymRebalance.swift
// Tempo
//
// Week assembly hook: when a persisted composite day (soccer + added gym
// session) precedes a day in the generated week, rebalance that day via the
// pure ExtraSessionRebalancer. Runs at the end of assembleWeekPlans, so
// loadWeekPlan, weekPlanSnapshot (Nutrition) and previewWeekPlans all agree.
// Only the generated (transient) template is changed — nothing is persisted.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    /// Rebalance the day after every persisted composite day in `plans`' window
    /// (the day before `monday` counts, so Monday follows a Sunday composite).
    func applyExtraSessionRebalance(to plans: [WorkoutPlan], monday: Date, modelContext: ModelContext) {
        let cal = Calendar.current
        guard let windowStart = cal.date(byAdding: .day, value: -1, to: monday),
              let windowEnd = cal.date(byAdding: .day, value: 7, to: monday)
        else {
            return
        }
        let persisted = (try? modelContext.fetch(FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.date >= windowStart && $0.date < windowEnd && $0.companionTypeRaw != nil }
        ))) ?? []
        guard !persisted.isEmpty else {
            return
        }
        let matchDays = Set(fetchUpcomingMatches(modelContext: modelContext).map { cal.startOfDay(for: $0.kickoff) })

        for composite in persisted {
            let day = cal.startOfDay(for: composite.date)
            guard let nextDay = cal.date(byAdding: .day, value: 1, to: day),
                  let tomorrow = plans.first(where: { cal.isDate($0.date, inSameDayAs: nextDay) }),
                  tomorrow.status == .planned,
                  tomorrow.programSessionKey == nil,
                  tomorrow.pausedReasonRaw == nil,
                  let dayAfter = cal.date(byAdding: .day, value: 1, to: nextDay)
            else {
                continue
            }
            let intensity = composite.addedPartIntensityRaw.flatMap(SessionIntensity.init(rawValue:)) ?? .moderate
            let preMatch = matchDays.contains(dayAfter)
                || plans.first(where: { cal.isDate($0.date, inSameDayAs: dayAfter) })?.type == .football
            guard let adjustment = ExtraSessionRebalancer.adjust(
                tomorrow: tomorrow.type,
                extraFocus: composite.type,
                extraIntensity: intensity,
                soccerLoad: soccerLoad(ofComposite: composite, modelContext: modelContext),
                tomorrowIsPreMatch: preMatch
            ) else {
                continue
            }
            if let newType = adjustment.newType {
                tomorrow.type = newType
                if !newType.isGymWorkout {
                    tomorrow.secondarySessionTypeRaw = nil
                }
            }
            tomorrow.recoveryAdjustment = max(
                ExtraSessionRebalancer.minRecoveryAdjustment,
                tomorrow.recoveryAdjustment * adjustment.recoveryScale
            )
            tomorrow.notes = tomorrow.notes.map { "\($0) \(adjustment.note)" } ?? adjustment.note
        }
    }

    /// How hard the composite day's soccer was, from its football session + sRPE.
    private func soccerLoad(ofComposite plan: WorkoutPlan, modelContext: ModelContext) -> SoccerLoad {
        let planID = plan.id
        let football = WorkoutType.football.rawValue
        let session = (try? modelContext.fetch(FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.workoutPlanID == planID && $0.workoutType == football }
        )))?.first
        return ExtraGymSessionPlanner.soccerLoad(.init(
            startMin: plan.companionStartMin ?? 0,
            durationMin: plan.companionDurationMin,
            strain: session?.strain,
            hardMinutes: session?.hardMinutes,
            sessionRPE: plan.companionSessionRPE
        ))
    }
}
