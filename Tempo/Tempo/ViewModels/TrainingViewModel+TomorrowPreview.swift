//
// TrainingViewModel+TomorrowPreview.swift
// Tempo
//
// Read-only preview of tomorrow's workout for the Tomorrow card: exercises,
// working sets x reps and target weights, plus the rebalance note when an
// extra gym session today reshaped it. NEVER persists anything: tomorrow's
// row must not exist before tomorrow (ensureTodayPlanPersisted would adopt it
// with stale recovery). Linking a transient plan to managed Exercise rows
// auto-inserts it into the context (verified by test), so the Sunday path —
// the only one that has to populate — builds the plan, copies it into value
// structs and deletes it again before any save.
//

import Foundation
import SwiftData

struct TomorrowPreview: Equatable {
    struct Row: Equatable, Identifiable {
        let id: Int
        let name: String
        let workingSets: Int
        let reps: Int
        /// Target load in kg (effective load for bodyweight lifts).
        let targetWeightKg: Double?
        let addedLoadKg: Double?
        let isBodyweight: Bool

        /// "4×6 @ 80 kg", "3×8 (BW)", "3×8 @ BW +10 kg".
        func detail(unit: WeightUnit) -> String {
            let head = "\(workingSets)×\(reps)"
            if isBodyweight {
                return "\(head) \(TodayWorkoutView.bodyweightLoadText(addedKg: addedLoadKg, unit: unit))"
            }
            if let kg = targetWeightKg, kg > 0 {
                let shown = TodayWorkoutView.weightText(WeightUnit.kg.convert(kg, to: unit))
                return "\(head) @ \(shown) \(unit.abbreviation)"
            }
            return "\(head) (BW)"
        }
    }

    let date: Date
    let type: WorkoutType
    let rows: [Row]
    /// "Adjusted: yesterday's soccer + push. ..." when today's extra session reshaped it.
    let note: String?
    let unit: WeightUnit

    var isGym: Bool {
        type.isGymWorkout
    }
}

extension TrainingViewModel {
    func tomorrowPreview(modelContext: ModelContext) -> TomorrowPreview? {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) else {
            return nil
        }
        let plan: WorkoutPlan
        var isFresh = false
        if let inWeek = weekPlans.first(where: { cal.isDate($0.date, inSameDayAs: tomorrow) }) {
            plan = inWeek
        } else if let previewed = previewWeekPlans(
            startingMonday: TrainingCalendar.mondayOfWeek(containing: tomorrow),
            modelContext: modelContext
        ).first(where: { cal.isDate($0.date, inSameDayAs: tomorrow) }) {
            // Sunday: tomorrow is next week's Monday, which weekPlans never holds.
            plan = previewed
            isFresh = true
        } else {
            return nil
        }

        if isFresh, plan.type.isGymWorkout {
            populateExercises(for: plan, modelContext: modelContext, recordPrediction: false)
        }
        let rows = Self.previewRows(from: plan)
        if isFresh, plan.modelContext != nil {
            // Populating auto-inserted the transient plan graph — drop it
            // (cascade) before anything can save it.
            modelContext.delete(plan)
        }

        var note: String?
        if let text = plan.notes, let range = text.range(of: "Adjusted:") {
            note = String(text[range.lowerBound...])
        }
        return TomorrowPreview(
            date: plan.date, type: plan.type, rows: rows, note: note,
            unit: currentWeightUnit(modelContext: modelContext)
        )
    }

    private static func previewRows(from plan: WorkoutPlan) -> [TomorrowPreview.Row] {
        plan.orderedExercises.enumerated().compactMap { index, slot in
            let working = slot.orderedSets.filter { !$0.isWarmup }
            guard let lead = working.first, let name = slot.exercise?.name ?? slot.exerciseNameSnapshot else {
                return nil
            }
            let isBodyweight = slot.exercise.map { StrengthStandards.isBodyweightLoaded($0.equipment) } ?? false
            return TomorrowPreview.Row(
                id: index, name: name, workingSets: working.count, reps: lead.targetReps,
                targetWeightKg: lead.targetWeight, addedLoadKg: lead.addedLoadKg, isBodyweight: isBodyweight
            )
        }
    }
}
