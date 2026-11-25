//
// TodayWorkoutView+TrainerAdjustment.swift
// Tempo
//
// §4 — the trainer's own target weight, shown on Today's exercise card when
// Tempo actually adjusted it (recovery multiplier / pain-note cap), plus a
// one-tap "Use trainer's weight" to restore it for the exercise's remaining
// sets today. Split out of TodayWorkoutView.swift to keep that file under
// the SwiftLint file/type-body length caps — same instance method, hosted
// in an extension.
//

import SwiftUI

extension TodayWorkoutView {
    /// "Trainer 60 kg → today 48 kg · recovery yellow −20%" with a one-tap
    /// way to use the trainer's own number instead, for a trainer-day
    /// exercise Tempo actually adjusted. Silent (no row) on every other
    /// exercise — a generated day never shows this, and an unadjusted
    /// trainer exercise looks exactly like it always did.
    @ViewBuilder
    func trainerAdjustmentRow(_ plannedExercise: PlannedExercise) -> some View {
        if let trainerKg = plannedExercise.trainerTargetKg,
           plannedExercise.loadAdjustmentNote != nil || plannedExercise.trainerOverrideApplied
        {
            let unit = settings?.weightUnit ?? .kg
            let trainerDisplay = WeightFormat.number(kg: trainerKg, unit: unit)
            HStack(alignment: .top, spacing: Tide.s1) {
                if plannedExercise.trainerOverrideApplied {
                    Label("Using trainer's \(trainerDisplay)\(unit.abbreviation)", systemImage: "checkmark.circle")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                } else {
                    let todayKg = plannedExercise.orderedSets.first(where: { !$0.isWarmup })?.targetWeight ?? trainerKg
                    let todayDisplay = WeightFormat.number(kg: todayKg, unit: unit)
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text("Trainer \(trainerDisplay)\(unit.abbreviation) → today \(todayDisplay)\(unit.abbreviation)")
                            .font(Tide.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(TideTrain.caution)
                        if let note = plannedExercise.displayLoadAdjustmentNote {
                            Text(note)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
                        }
                    }
                    Spacer(minLength: Tide.s2)
                    Button("Use trainer's weight") {
                        viewModel.useTrainerWeight(for: plannedExercise, modelContext: modelContext)
                    }
                    .font(Tide.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, Tide.hair)
        }
    }
}
