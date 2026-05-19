//
// ActiveWorkoutView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Active Workout View

// Per MODULE_TRAINING.md Section 3 — Exercise-by-exercise set logging.
// Per STATE_MACHINES.md Section 1 — Workout session states.

struct ActiveWorkoutView: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var inputWeight: Double = 0
    @State
    private var inputReps: Double = 8
    @State
    private var inputRPE: Int?
    @State
    private var showFinishConfirmation = false
    @Query
    private var allSettings: [UserSettings]

    /// User weight-unit preference. The stepper edits a *display* value in
    /// this unit; storage stays kg (converted at the log boundary) so
    /// volume/PR/history math is never corrupted.
    private var weightUnit: WeightUnit {
        allSettings.first?.weightUnit ?? .kg
    }

    /// Stepper increment in the display unit: 2.5 kg vs a realistic 5 lb
    /// plate jump.
    private var weightStep: Double {
        weightUnit == .kg ? 2.5 : 5
    }

    /// Upper bound in the display unit (≈ 500 kg).
    private var weightRangeMax: Double {
        weightUnit == .kg ? 500 : 1100
    }

    var body: some View {
        ZStack {
            Color.tempoBgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Timer bar
                timerBar

                // Content based on state
                switch viewModel.sessionState {
                case .warmup:
                    warmupContent

                case .exercise(.setActive):
                    setActiveContent

                case .exercise(.resting):
                    RestTimerView(viewModel: viewModel)

                case let .exercise(.betweenExercises(_, toIndex)):
                    exerciseTransition(toIndex: toIndex)

                case .cooldown:
                    cooldownContent

                case .paused:
                    pausedOverlay

                case .crashedRecovery:
                    crashRecoveryContent

                default:
                    EmptyView()
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFinishConfirmation = true
                } label: {
                    Text("Finish")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        .alert("Finish Workout?", isPresented: $showFinishConfirmation) {
            Button("Save & Finish", role: .destructive) {
                viewModel.finishWorkout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This ends and saves your session.")
        }
        .onAppear { loadCurrentSetInputs() }
        .onChange(of: viewModel.currentExerciseIndex) { _, _ in loadCurrentSetInputs() }
        .onChange(of: viewModel.currentSetIndex) { _, _ in loadCurrentSetInputs() }
        // Per build done_when #12 — present SetFeedbackSheet for the set just
        // completed via Finish Set. Cleared on dismiss; not re-prompted.
        .sheet(
            isPresented: Binding(
                get: { viewModel.lastCompletedSet != nil },
                set: { presented in
                    if !presented { viewModel.lastCompletedSet = nil }
                }
            )
        ) {
            if let set = viewModel.lastCompletedSet {
                SetFeedbackSheet(plannedSet: set)
            }
        }
    }

    // MARK: - Timer Bar

    private var timerBar: some View {
        HStack {
            // Elapsed time
            Text(viewModel.formattedElapsedTime)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
                .monospacedDigit()

            Spacer()

            // Progress
            Text("\(viewModel.completedSets)/\(viewModel.totalSets) sets")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            Spacer()

            // Volume
            Text(viewModel.formattedVolume)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoSurfaceCard)
    }

    // MARK: - Set Active Content

    // Per MODULE_TRAINING.md Section 3 — Weight/reps inputs, DONE button

    private var setActiveContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Exercise info
                exerciseHeader

                // Set counter
                Text(viewModel.setCountText)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)

                // Weight input
                VStack(spacing: TempoSpacing.sm) {
                    Text("WEIGHT")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    NumberStepperView(
                        value: $inputWeight,
                        range: 0 ... weightRangeMax,
                        step: weightStep,
                        format: weightUnit == .kg ? "%.1f" : "%.0f",
                        unit: weightUnit.abbreviation
                    )
                }

                // Reps input
                VStack(spacing: TempoSpacing.sm) {
                    Text("REPS")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    NumberStepperView(
                        value: $inputReps,
                        range: 1 ... 100,
                        step: 1,
                        format: "%.0f",
                        unit: "reps"
                    )
                }

                // RPE selector (optional)
                rpeSelector

                // Set progress
                setProgress

                // Done button
                Button {
                    // inputWeight is in the user's display unit; persist kg.
                    let weightKg = weightUnit.convert(inputWeight, to: .kg)
                    viewModel.logSet(
                        weight: weightKg,
                        reps: Int(inputReps),
                        rpe: inputRPE,
                        modelContext: modelContext
                    )
                    HapticManager.notification(.success)
                } label: {
                    Text("Finish Set")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.tempoSignal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.lg)
        }
    }

    // MARK: - Warmup Content

    // Per STATE_MACHINES.md §1 and build done_when #7 — display-only warmup
    // prompt. Lists the first exercise's warmup sets as target guidance;
    // "Ready — Start Working Sets" skips straight to the first working set
    // (warmup is never logged). Weights shown in the user's unit, matching
    // the set-input stepper.

    private var warmupContent: some View {
        let firstExercise = viewModel.todayPlan?.orderedExercises.first
        let warmupSets = (firstExercise?.orderedSets ?? []).filter(\.isWarmup)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                VStack(spacing: TempoSpacing.xs) {
                    Text("WARM-UP")
                        .font(.tempoCaption1)
                        .tracking(TempoTracking.drillLabel)
                        .foregroundStyle(Color.tempoTextTertiary)

                    Text(firstExercise?.exercise?.name ?? "First Exercise")
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .multilineTextAlignment(.center)

                    Text("Two warm-up sets. Ramp up, then hit your working sets.")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, TempoSpacing.xl)

                VStack(spacing: TempoSpacing.sm) {
                    ForEach(Array(warmupSets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("Set \(index + 1)")
                                .font(.tempoHeadline)
                                .foregroundStyle(Color.tempoTextSecondary)
                            Spacer()
                            Text(warmupTargetLabel(set))
                                .font(.tempoHeadline)
                                .monospacedDigit()
                                .foregroundStyle(Color.tempoTextPrimary)
                        }
                        .padding(TempoSpacing.cardPadding)
                        .background(Color.tempoSurfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)

                Button {
                    viewModel.advancePastWarmup()
                    HapticManager.notification(.success)
                } label: {
                    Text("Ready — Start Working Sets")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.tempoSignal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
            }
            .padding(.vertical, TempoSpacing.lg)
        }
    }

    private func warmupTargetLabel(_ set: PlannedSet) -> String {
        if let w = set.targetWeight, w > 0 {
            let display = WeightUnit.kg.convert(w, to: weightUnit)
            return "\(Int(display)) \(weightUnit.abbreviation) × \(set.targetReps)"
        }
        return "Bodyweight × \(set.targetReps)"
    }

    // MARK: - Exercise Header

    private var exerciseHeader: some View {
        VStack(spacing: TempoSpacing.xs) {
            if let exercise = viewModel.currentExercise?.exercise {
                Text(exercise.name.uppercased())
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .multilineTextAlignment(.center)

                Text(exercise.muscleGroup.displayName)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .padding(.top, TempoSpacing.md)
    }

    // MARK: - RPE Selector

    private var rpeSelector: some View {
        VStack(spacing: TempoSpacing.sm) {
            Text("RPE (optional)")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            HStack(spacing: TempoSpacing.xs) {
                ForEach(6 ... 10, id: \.self) { rpe in
                    Button {
                        inputRPE = inputRPE == rpe ? nil : rpe
                    } label: {
                        Text("\(rpe)")
                            .font(.tempoCaption1)
                            .fontWeight(.medium)
                            .frame(width: 40, height: 40)
                            .background(inputRPE == rpe ? Color.tempoSignal : Color.tempoSurfaceCard)
                            .foregroundStyle(inputRPE == rpe ? .white : Color.tempoTextPrimary)
                            .clipShape(Circle())
                    }
                }
            }
        }
    }

    // MARK: - Set Progress

    private var setProgress: some View {
        VStack(spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.xs) {
                if let exercise = viewModel.currentExercise {
                    // Iterate the elements by stable id — never index into
                    // orderedSets by position. The +/- buttons mutate this
                    // array; a ForEach over `.indices` keeps a stale range
                    // and crashes (Index out of range) on the next render.
                    ForEach(Array(exercise.orderedSets.enumerated()), id: \.element.id) { idx, set in
                        if set.isWarmup {
                            // Warmup sets shown as smaller, outlined dots
                            Circle()
                                .stroke(setDotColor(set: set, index: idx), lineWidth: 1.5)
                                .frame(width: 10, height: 10)
                        } else {
                            Circle()
                                .fill(setDotColor(set: set, index: idx))
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }

            // +/- set buttons
            HStack(spacing: TempoSpacing.md) {
                Button {
                    viewModel.removeLastUncompletedSet(
                        from: viewModel.currentExerciseIndex,
                        modelContext: modelContext
                    )
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .disabled((viewModel.currentExercise?.orderedSets.count ?? 0) <= 1)

                Text("\(viewModel.workingSetCount) sets")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)

                Button {
                    viewModel.addSet(
                        to: viewModel.currentExerciseIndex,
                        modelContext: modelContext
                    )
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoSignal)
                }
            }
        }
    }

    private func setDotColor(set: PlannedSet, index: Int) -> Color {
        if set.completed {
            Color.tempoRecoveryGreen
        } else if index == viewModel.currentSetIndex {
            Color.tempoSignal
        } else {
            Color.tempoTextTertiary.opacity(0.3)
        }
    }

    // MARK: - Exercise Transition

    private func exerciseTransition(toIndex: Int) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()

            Text("NEXT EXERCISE")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)

            if let plan = viewModel.todayPlan {
                let exercises = plan.orderedExercises
                if toIndex < exercises.count, let name = exercises[toIndex].exercise?.name {
                    Text(name.uppercased())
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
            }

            ProgressView()

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cooldown Content

    private var cooldownContent: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.tempoRecoveryGreen)

            Text("WORKOUT COMPLETE!")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)

            if !viewModel.detectedPRs.isEmpty {
                VStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.tempoPRGold)

                    Text("\(viewModel.detectedPRs.count) PR\(viewModel.detectedPRs.count > 1 ? "s" : "") Hit!")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
            }

            Button {
                viewModel.skipCooldown()
            } label: {
                Text("VIEW SUMMARY")
                    .font(.tempoHeadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.tempoSignal)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            }
            .padding(.horizontal, TempoSpacing.screenEdge)

            Spacer()
        }
    }

    // MARK: - Paused Overlay

    private var pausedOverlay: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Image(systemName: "pause.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.tempoTextTertiary)

            Text("PAUSED")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)

            Text(viewModel.formattedElapsedTime)
                .font(.tempoDataLarge)
                .foregroundStyle(Color.tempoTextSecondary)
                .monospacedDigit()

            VStack(spacing: TempoSpacing.md) {
                Button {
                    viewModel.resume()
                } label: {
                    Text("RESUME")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.tempoSignal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }

                Button {
                    showFinishConfirmation = true
                } label: {
                    Text("End Workout")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoRecoveryRed)
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)

            Spacer()
        }
    }

    // MARK: - Crash Recovery Content

    private var crashRecoveryContent: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoRecoveryYellow)

            Text("Resume Your Workout?")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("It looks like a workout was in progress.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)

            VStack(spacing: TempoSpacing.md) {
                Button {
                    viewModel.resumeFromCrash()
                } label: {
                    Text("RESUME WORKOUT")
                        .font(.tempoHeadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.tempoSignal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                }

                Button {
                    viewModel.discardCrashedWorkout(modelContext: modelContext)
                    dismiss()
                } label: {
                    Text("Discard")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoRecoveryRed)
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func loadCurrentSetInputs() {
        // Per MODULE_TRAINING.md — sticky weight from previous set.
        // stickyWeight is kg-stored; convert to the display unit and snap to
        // the stepper grid so the first +/- tap lands on a clean increment
        // (a 60 kg sticky → 132.28 lb would otherwise step to 137.28).
        if let stickyKg = viewModel.stickyWeight {
            let display = WeightUnit.kg.convert(stickyKg, to: weightUnit)
            inputWeight = (display / weightStep).rounded() * weightStep
        }
        if let targetReps = viewModel.currentSet?.targetReps {
            inputReps = Double(targetReps)
        }
        inputRPE = nil
    }
}
