//
// TrainingViewModel+Travel.swift
// Tempo
//
// "Limited equipment today/this week" (pause/travel-pain feature). New file —
// see `TravelEquipmentPeriod.swift` (model) and `TravelSwapEngine.swift`
// (pure matching). The actual swap is applied inside
// `TrainingViewModel.populateFromTrainerProgram`
// (`TrainingViewModel+TrainerProgram.swift`'s per-exercise loop) via
// `travelSwapReplacement(for:modelContext:)` below — kept here, not inlined
// there, so that file's diff stays a single small addition (see its own
// comment at the call site).
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Fetch

    func fetchTravelEquipmentPeriods(modelContext: ModelContext) -> [TravelEquipmentPeriod] {
        (try? modelContext.fetch(FetchDescriptor<TravelEquipmentPeriod>())) ?? []
    }

    /// The travel-equipment period covering `date`, if any.
    func activeTravelEquipmentPeriod(asOf date: Date = Date(), modelContext: ModelContext) -> TravelEquipmentPeriod? {
        fetchTravelEquipmentPeriods(modelContext: modelContext)
            .filter { $0.covers(date) }
            .max { $0.createdAt < $1.createdAt }
    }

    /// Starts (or replaces) the active travel-equipment period, then
    /// immediately re-populates today's still-`.planned` trainer exercises so
    /// the swap is visible right away instead of waiting for the next natural
    /// regeneration — same "force a repopulate now" pattern
    /// `reapplyEditedProgramToday` already uses for a program edit.
    @discardableResult
    func startTravelEquipmentPeriod(
        scope: TravelEquipmentScope,
        availableEquipment: Set<Equipment>,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> TravelEquipmentPeriod {
        for open in fetchTravelEquipmentPeriods(modelContext: modelContext) where open.covers(now) {
            open.endedAt = now
        }
        let period = TravelEquipmentPeriod(scope: scope, availableEquipment: Array(availableEquipment), startDate: now)
        modelContext.insert(period)
        _ = modelContext.saveOrAlert("start travel equipment period")
        reapplyTravelSwapsToday(modelContext: modelContext)
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
        HapticManager.selection()
        return period
    }

    func endTravelEquipmentPeriod(_ period: TravelEquipmentPeriod, modelContext: ModelContext, now: Date = Date()) {
        period.endedAt = now
        _ = modelContext.saveOrAlert("end travel equipment period")
        reapplyTravelSwapsToday(modelContext: modelContext)
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
    }

    /// Re-populate today's `.planned` trainer-program exercises so a
    /// just-started/just-ended travel period is reflected immediately.
    /// Mirrors `reapplyEditedProgramToday`'s exact guard/rebuild shape.
    private func reapplyTravelSwapsToday(modelContext: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<WorkoutPlan>(predicate: #Predicate<WorkoutPlan> { $0.date == today })
        guard let plans = try? modelContext.fetch(descriptor) else {
            return
        }
        var changed = false
        for plan in plans where plan.status == .planned && plan.programSessionKey != nil {
            for exercise in plan.orderedExercises {
                modelContext.delete(exercise)
            }
            plan.exercises = []
            _ = populateFromTrainerProgram(plan, modelContext: modelContext)
            changed = true
        }
        guard changed else {
            return
        }
        _ = modelContext.saveOrAlert("travel swap re-apply")
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
    }

    // MARK: - Swap resolution

    /// If a travel-equipment period covers `planDate` AND `exercise`'s own
    /// equipment isn't in the available set, the closest same-pattern/
    /// same-muscle library replacement — else nil (no active period, or the
    /// exercise's equipment is already fine). Called from
    /// `populateFromTrainerProgram`'s per-exercise loop.
    func travelSwapReplacement(
        for exercise: Exercise,
        planDate: Date,
        library: [Exercise],
        modelContext: ModelContext
    ) -> Exercise? {
        guard let period = activeTravelEquipmentPeriod(asOf: planDate, modelContext: modelContext),
              !TravelSwapEngine.isUsable(exercise.equipment, available: period.availableEquipment)
        else {
            return nil
        }
        let candidates = library.map {
            TravelSwapEngine.Candidate(
                id: $0.id, name: $0.name, equipment: $0.equipment,
                movementPattern: $0.movementPattern, muscleGroup: $0.muscleGroup, isCompound: $0.isCompound
            )
        }
        let source = TravelSwapEngine.Candidate(
            id: exercise.id, name: exercise.name, equipment: exercise.equipment,
            movementPattern: exercise.movementPattern, muscleGroup: exercise.muscleGroup, isCompound: exercise.isCompound
        )
        guard let picked = TravelSwapEngine.pickReplacement(for: source, in: candidates, available: period.availableEquipment),
              let replacement = library.first(where: { $0.id == picked.id })
        else {
            return nil
        }
        return replacement
    }
}
