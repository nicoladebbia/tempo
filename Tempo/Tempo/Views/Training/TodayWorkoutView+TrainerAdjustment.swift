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
            let trainerDisplay = Int(WeightUnit.kg.convert(trainerKg, to: unit).rounded())
            HStack(alignment: .top, spacing: TempoSpacing.xs) {
                if plannedExercise.trainerOverrideApplied {
                    Label("Using trainer's \(trainerDisplay)\(unit.abbreviation)", systemImage: "checkmark.circle")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                } else {
                    let todayKg = plannedExercise.orderedSets.first(where: { !$0.isWarmup })?.targetWeight ?? trainerKg
                    let todayDisplay = Int(WeightUnit.kg.convert(todayKg, to: unit).rounded())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trainer \(trainerDisplay)\(unit.abbreviation) → today \(todayDisplay)\(unit.abbreviation)")
                            .font(.tempoCaption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tempoWarning)
                        if let note = plannedExercise.loadAdjustmentNote {
                            Text(note)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                    Spacer(minLength: TempoSpacing.sm)
                    Button("Use trainer's weight") {
                        viewModel.useTrainerWeight(for: plannedExercise, modelContext: modelContext)
                    }
                    .font(.tempoCaption2.weight(.semibold))
                    .foregroundStyle(Color.tempoSignal)
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }
}
