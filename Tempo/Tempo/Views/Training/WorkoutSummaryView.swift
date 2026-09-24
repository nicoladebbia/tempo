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

    /// §8.2 completion ring animation state.
    @State
    private var ringProgress: Double = 0
    @State
    private var checkScale: Double = 0.3

    /// Completed working sets over planned working sets (warmups excluded).
    /// No sets at all → 1.0 (nothing was cut short).
    private var completionFraction: Double {
        guard let plan = viewModel.todayPlan else {
            return 1
        }
        let working = plan.orderedExercises
            .flatMap { $0.sets ?? [] }
            .filter { !$0.isWarmup }
        guard !working.isEmpty else {
            return 1
        }
        return Double(working.filter(\.completed).count) / Double(working.count)
    }

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

                // §4 — trainer-program exercises Tempo adjusted (recovery/pain
                // note) or that the athlete overrode back to the trainer's number.
                trainerAdjustmentsSection

                // Per-exercise summary
                exerciseSummary

                // The athlete's own notes — saved with the workout.
                if let plan = viewModel.todayPlan {
                    SessionNotesField(plan: plan)
                }

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
            // §8.2 — completion RING (was a static checkmark): sweeps to the
            // fraction of working sets actually completed, so a cut-short
            // session visibly reads as partial, not falsely "done".
            ZStack {
                Circle()
                    .stroke(Color.tempoSurfaceCard, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        Color.tempoRecoveryGreen,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.tempoRecoveryGreen)
                    .scaleEffect(checkScale)
            }
            .frame(width: 96, height: 96)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    ringProgress = completionFraction
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.5)) {
                    checkScale = 1
                }
            }

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

                        // §15 fix — `pr.context` is a kg-only, unit-unaware
                        // string from TrainingEngine ("82kg x 5 reps" even
                        // for an lbs user). PRDisplay never renders that
                        // embedded weight; the number on the right already
                        // shows pr.value converted to the user's unit.
                        Text(PRDisplay.subtitle(pr))
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextSecondary)
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

    // MARK: - Trainer Adjustments (§4)

    /// Exercises with a recorded `loadAdjustmentNote` (Tempo changed the
    /// trainer's number) or an applied override (the athlete used the
    /// trainer's own number instead). Empty on a generated day.
    private var trainerAdjustedExercises: [PlannedExercise] {
        (viewModel.todayPlan?.orderedExercises ?? []).filter {
            $0.loadAdjustmentNote != nil || $0.trainerOverrideApplied
        }
    }

    @ViewBuilder
    private var trainerAdjustmentsSection: some View {
        if !trainerAdjustedExercises.isEmpty {
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                Text("Trainer Adjustments")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)

                ForEach(trainerAdjustedExercises, id: \.id) { plannedEx in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plannedEx.displayName)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Text(
                                plannedEx.trainerOverrideApplied
                                    ? "Used the trainer's own weight"
                                    : (plannedEx.loadAdjustmentNote ?? "Adjusted")
                            )
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                        }
                        Spacer()
                        Image(systemName: plannedEx.trainerOverrideApplied ? "arrow.uturn.backward.circle" : "slider.horizontal.3")
                            .foregroundStyle(Color.tempoWarning)
                    }
                    .padding(TempoSpacing.md)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
                }
            }
        }
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
                    // Fix #9 — "x 8 / side", or "x L8 / R7" for a logged split.
                    let repsText = SideRepsFormat.loggedReps(
                        actual: reps, left: best.actualRepsLeft, right: best.actualRepsRight,
                        perSide: plannedEx.perSide
                    )
                    Text("Best: \(formattedWeight(weight)) x \(repsText)")
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
                // §4 fix — only close on success. saveWorkout leaves
                // saveErrorMessage set (and sessionState still .summary) on
                // failure; dismissing anyway threw away the only screen with
                // a SAVE button to retry from, while the loud "Save failed"
                // alert popped up over an already-closed summary.
                if viewModel.saveErrorMessage == nil {
                    dismiss()
                }
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
