//
// WorkoutSummaryView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Workout Summary View

// Per MODULE_TRAINING.md Section 8 — Post-workout summary.
// Per STATE_MACHINES.md Section 1 — summary → saved.

struct WorkoutSummaryView: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Header
                headerSection

                // Last-set feedback — the final working set goes straight to the
                // summary (no rest, no cooldown screen), so its RPE/note is
                // captured here. Save-on-change like the in-session panel.
                if viewModel.currentFeedback != nil {
                    InlineSetFeedbackView(viewModel: viewModel)
                }

                // PR badges (if any)
                if !viewModel.detectedPRs.isEmpty {
                    prSection
                }

                // Stats grid
                statsGrid

                // Warm-up marker (the guided mobility block logs no sets).
                if viewModel.todayPlan?.warmupCompleted == true {
                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.tempoRecoveryGreen)
                        Text("Warm-up completed")
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Per-exercise summary
                exerciseSummary

                // Save button
                saveButton
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationBarBackButtonHidden()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: TempoSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.tempoRecoveryGreen)

            Text("WORKOUT COMPLETE")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)

            if let plan = viewModel.todayPlan {
                Text(plan.type.displayName.uppercased())
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .padding(.top, TempoSpacing.xxl)
    }

    // MARK: - PR Section

    // Per MODULE_TRAINING.md Section 8 — Gold badge for PRs

    private var prSection: some View {
        VStack(spacing: TempoSpacing.md) {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "trophy.fill")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoPRGold) // gold

                Text("\(viewModel.detectedPRs.count) Personal Record\(viewModel.detectedPRs.count > 1 ? "s" : "")!")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
            }

            ForEach(viewModel.detectedPRs, id: \.id) { pr in
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "star.fill")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoPRGold)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pr.exercise?.name ?? "Exercise")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)

                        if let context = pr.context {
                            Text(context)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }

                    Spacer()

                    Text(formattedWeight(pr.value, decimals: 1))
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
                .padding(TempoSpacing.md)
                .background(Color.tempoPRGold.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: TempoSpacing.sm),
            GridItem(.flexible(), spacing: TempoSpacing.sm),
        ], spacing: TempoSpacing.sm) {
            statCell(
                icon: "timer",
                label: "Duration",
                value: viewModel.formattedElapsedTime
            )
            statCell(
                icon: "scalemass",
                label: "Volume",
                value: viewModel.formattedVolume
            )
            statCell(
                icon: "checkmark.circle",
                label: "Sets",
                value: "\(viewModel.completedSets)"
            )
            statCell(
                icon: "flame",
                label: "Exercises",
                value: "\(viewModel.totalExercises)"
            )
        }
    }

    private func statCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            Image(systemName: icon)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)

            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            Text(value)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.lg)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Per-Exercise Summary

    private var exerciseSummary: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("Exercise Summary")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)

            if let plan = viewModel.todayPlan {
                ForEach(plan.orderedExercises, id: \.id) { plannedEx in
                    exerciseSummaryRow(plannedEx)
                }
            }
        }
    }

    private func exerciseSummaryRow(_ plannedEx: PlannedExercise) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(plannedEx.exercise?.name ?? "Exercise")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)

                // Best set
                if let best = plannedEx.bestSet,
                   let weight = best.actualWeight,
                   let reps = best.actualReps
                {
                    Text("Best: \(formattedWeight(weight)) x \(reps)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }

            Spacer()

            // Volume for this exercise
            let vol = plannedEx.totalVolume
            if vol > 0 {
                Text(formattedWeight(vol))
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            // Completion indicator
            Image(systemName: plannedEx.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.tempoBody)
                .foregroundStyle(
                    plannedEx.isComplete ? Color.tempoRecoveryGreen : Color.tempoTextTertiary
                )
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Weight Formatting

    /// Format a kg-stored weight in the user's display unit. Keeps the summary
    /// consistent with the timer-bar volume (which already converts) — fixes the
    /// bug where per-set/per-exercise rows were hardcoded "kg" while the volume
    /// header showed the user's actual unit.
    private func formattedWeight(_ kg: Double, decimals: Int = 0) -> String {
        let value = WeightUnit.kg.convert(kg, to: viewModel.weightUnit)
        let unit = viewModel.weightUnit.abbreviation
        return String(format: "%.\(decimals)f %@", value, unit)
    }

    // MARK: - Save Button

    // Per STATE_MACHINES.md — summary → saved

    private var saveButton: some View {
        Button {
            Task {
                await viewModel.saveWorkout(modelContext: modelContext)
                dismiss()
            }
        } label: {
            Text("SAVE & CLOSE")
                .font(.tempoHeadline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.tempoSignal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
        }
    }
}
