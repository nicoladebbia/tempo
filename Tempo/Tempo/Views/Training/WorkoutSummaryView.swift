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
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// §8.2 completion ring animation state.
    @State
    private var ringProgress: Double = 0
    /// Fix #8 — "send report to trainer" entry point (TrainerReportSheet.swift, new file).
    @State
    private var showTrainerReport = false

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
            VStack(spacing: Tide.s5) {
                // Header
                headerSection

                // PR badges (if any): the best news comes first.
                if !viewModel.detectedPRs.isEmpty {
                    prSection
                }

                // Stats
                statsCard

                // Last-set feedback — the final working set goes straight to the
                // summary (no rest, no cooldown screen), so its RPE/note is
                // captured here. Save-on-change like the in-session panel.
                if viewModel.currentFeedback != nil {
                    InlineSetFeedbackView(viewModel: viewModel)
                }

                // trainer-feedback-tests — "New max: Squat 120 kg — your
                // trainer's 75% is now 90 kg." / "New best: 30m in 4.30″".
                if !viewModel.testResultMessages.isEmpty {
                    testResultSection
                }

                // Warm-up marker (the guided mobility block logs no sets).
                if viewModel.todayPlan?.warmupCompleted == true {
                    TrainTag(text: "Warm-up completed", systemImage: "checkmark.seal.fill", color: TideTrain.positive)
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
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s6)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        // The summary is a cover opened from a page: draw its own field.
        .trainSheetRoot(energy: 0.8)
        .safeAreaBar(edge: .bottom) {
            saveButton
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s2)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            if viewModel.todayPlan?.programSessionKey != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showTrainerReport = true
                    } label: {
                        Image(systemName: "paperplane")
                    }
                    .accessibilityLabel("Send report to trainer")
                }
            }
        }
        .sheet(isPresented: $showTrainerReport) {
            if let program = TrainerReportSheet.program(
                forSessionKey: viewModel.todayPlan?.programSessionKey,
                modelContext: modelContext
            ) {
                TrainerReportSheet(program: program)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Tide.s4) {
            // §8.2 — completion RING (was a static checkmark): sweeps to the
            // fraction of working sets actually completed, so a cut-short
            // session visibly reads as partial, not falsely "done".
            TrainRing(
                progress: ringProgress,
                tint: completionFraction >= 1 ? TideTrain.positive : TideTrain.caution,
                diameter: TideTrainSession.summaryRing
            ) {
                VStack(spacing: Tide.hair) {
                    TideNumber(
                        "\(Int((completionFraction * 100).rounded()))",
                        unit: "%",
                        size: TideTrainSession.ringClock,
                        relativeTo: .largeTitle
                    )
                    Text("Sets done").tideLabel()
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sets done")
            .accessibilityValue("\(Int((completionFraction * 100).rounded())) percent")
            .onAppear {
                if reduceMotion {
                    ringProgress = completionFraction
                } else {
                    withAnimation(Tide.settle) {
                        ringProgress = completionFraction
                    }
                }
            }

            VStack(spacing: Tide.s1) {
                Text("Workout complete")
                    .font(Tide.title)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)

                if let plan = viewModel.todayPlan {
                    Text(plan.type.displayName).tideLabel()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Tide.s4)
    }

    // MARK: - PR Section

    // Per MODULE_TRAINING.md Section 8 — Gold badge for PRs

    private var prSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(spacing: Tide.s2) {
                Image(systemName: "trophy.fill")
                    .font(Tide.headline)
                    .foregroundStyle(TideTrain.record) // gold
                    .accessibilityHidden(true)

                Text("\(viewModel.detectedPRs.count) Personal Record\(viewModel.detectedPRs.count > 1 ? "s" : "")!")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
            }

            ForEach(Array(viewModel.detectedPRs.enumerated()), id: \.element.id) { index, pr in
                if index > 0 {
                    TrainSessionRule()
                }
                HStack(spacing: Tide.s3) {
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(pr.exercise?.name ?? "Exercise")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)

                        // §15 fix — `pr.context` is a kg-only, unit-unaware
                        // string from TrainingEngine ("82kg x 5 reps" even
                        // for an lbs user). PRDisplay never renders that
                        // embedded weight; the number on the right already
                        // shows pr.value converted to the user's unit.
                        Text(PRDisplay.subtitle(pr))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }

                    Spacer(minLength: Tide.s2)

                    Text(PRDisplay.valueLabel(pr, unit: viewModel.weightUnit))
                        .font(TideTrain.figure(.title3))
                        .foregroundStyle(TideTrain.record)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .trainSessionOutline(TideTrain.record)
    }

    // MARK: - Test Result Section (trainer-feedback-tests)

    private var testResultSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            ForEach(Array(viewModel.testResultMessages.enumerated()), id: \.offset) { index, message in
                if index > 0 {
                    TrainSessionRule()
                }
                HStack(alignment: .top, spacing: Tide.s3) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(Tide.body)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    // MARK: - Stats

    private var statsCard: some View {
        // Two across; one column at the accessibility sizes so a long volume
        // ("12,480 kg") never squeezes its neighbour.
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Tide.s4, alignment: .topLeading),
                count: typeSize.isAccessibilitySize ? 1 : 2
            ),
            alignment: .leading,
            spacing: Tide.s4
        ) {
            TrainStat(value: viewModel.formattedElapsedTime, label: "Duration")
            TrainStat(value: viewModel.formattedVolume, label: "Volume")
            TrainStat(value: "\(viewModel.completedSets)", label: "Sets")
            TrainStat(value: "\(viewModel.performedExercises)", label: "Exercises")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s5, radius: Tide.tileRadius)
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
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: "Trainer adjustments")

                VStack(alignment: .leading, spacing: Tide.s3) {
                    ForEach(Array(trainerAdjustedExercises.enumerated()), id: \.element.id) { index, plannedEx in
                        if index > 0 {
                            TrainSessionRule()
                        }
                        HStack(alignment: .top, spacing: Tide.s3) {
                            VStack(alignment: .leading, spacing: Tide.hair) {
                                Text(plannedEx.displayName)
                                    .font(Tide.bodyStrong)
                                    .foregroundStyle(Tide.text)
                                Text(
                                    plannedEx.trainerOverrideApplied
                                        ? "Used the trainer's own weight"
                                        : (plannedEx.loadAdjustmentNote ?? "Adjusted")
                                )
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: Tide.s2)
                            Image(systemName: plannedEx.trainerOverrideApplied ? "arrow.uturn.backward.circle" : "slider.horizontal.3")
                                .foregroundStyle(TideTrain.caution)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
        }
    }

    // MARK: - Per-Exercise Summary

    private var exerciseSummary: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Exercise summary")

            if let plan = viewModel.todayPlan {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    ForEach(Array(plan.orderedExercises.enumerated()), id: \.element.id) { index, plannedEx in
                        if index > 0 {
                            TrainSessionRule()
                        }
                        exerciseSummaryRow(plannedEx)
                    }
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            }
        }
    }

    private func exerciseSummaryRow(_ plannedEx: PlannedExercise) -> some View {
        let row = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        let working = plannedEx.orderedSets.filter { !$0.isWarmup }
        return row {
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(plannedEx.exercise?.name ?? "Exercise")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)

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
                    let isBodyweight = plannedEx.exercise.map { StrengthStandards.isBodyweightLoaded($0.equipment) } ?? false
                    let loadText = WeightFormat.setLoad(
                        kg: weight, addedKg: best.addedLoadKg, bodyweight: isBodyweight, unit: viewModel.weightUnit
                    )
                    Text("Best: \(loadText) × \(repsText)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }

                // One tick per working set: a cut-short exercise shows its gap.
                if !working.isEmpty {
                    TrainSetTicks(done: working.filter(\.completed).count, total: working.count)
                        .padding(.top, Tide.s1)
                }
            }

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Tide.s2)
            }

            // Volume for this exercise
            let vol = plannedEx.totalVolume
            if vol > 0 {
                Text(WeightFormat.volumeText(kg: vol, unit: viewModel.weightUnit))
                    .font(TideTrain.figure(.footnote))
                    .foregroundStyle(Tide.text2)
            }

            // Completion indicator
            Image(systemName: plannedEx.isComplete ? "checkmark.circle.fill" : "circle")
                .font(Tide.headline)
                .foregroundStyle(
                    plannedEx.isComplete ? TideTrain.positive : Tide.text3
                )
                .accessibilityLabel(plannedEx.isComplete ? "Done" : "Not finished")
        }
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
            Text("Save & close")
        }
        .buttonStyle(.tidePrimary)
        .sensoryFeedback(.success, trigger: viewModel.completedSets)
    }
}
