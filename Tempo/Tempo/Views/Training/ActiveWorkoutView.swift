import SwiftUI
import SwiftData

// MARK: - Active Workout View
// Per MODULE_TRAINING.md Section 3 — Exercise-by-exercise set logging.
// Per STATE_MACHINES.md Section 1 — Workout session states.

struct ActiveWorkoutView: View {

    @Bindable var viewModel: TrainingViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var inputWeight: Double = 0
    @State private var inputReps: Double = 8
    @State private var inputRPE: Int?
    @State private var showFinishConfirmation = false

    var body: some View {
        ZStack {
            Color.tempoBgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Timer bar
                timerBar

                // Content based on state
                switch viewModel.sessionState {
                case .exercise(.setActive):
                    setActiveContent

                case .exercise(.resting):
                    RestTimerView(viewModel: viewModel)

                case .exercise(.betweenExercises(_, let toIndex)):
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
        .confirmationDialog("Finish Workout?", isPresented: $showFinishConfirmation) {
            Button("Save & Finish") { viewModel.finishWorkout() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { loadCurrentSetInputs() }
        .onChange(of: viewModel.currentExerciseIndex) { _, _ in loadCurrentSetInputs() }
        .onChange(of: viewModel.currentSetIndex) { _, _ in loadCurrentSetInputs() }
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
                        range: 0...500,
                        step: 2.5,
                        format: "%.1f",
                        unit: "kg"
                    )
                }

                // Reps input
                VStack(spacing: TempoSpacing.sm) {
                    Text("REPS")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    NumberStepperView(
                        value: $inputReps,
                        range: 1...100,
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
                    viewModel.logSet(
                        weight: inputWeight,
                        reps: Int(inputReps),
                        rpe: inputRPE,
                        modelContext: modelContext
                    )
                    HapticManager.notification(.success)
                } label: {
                    Text("DONE")
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
                ForEach(6...10, id: \.self) { rpe in
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
        HStack(spacing: TempoSpacing.xs) {
            if let exercise = viewModel.currentExercise {
                ForEach(exercise.orderedSets.indices, id: \.self) { idx in
                    let set = exercise.orderedSets[idx]
                    Circle()
                        .fill(setDotColor(set: set, index: idx))
                        .frame(width: 12, height: 12)
                }
            }
        }
    }

    private func setDotColor(set: PlannedSet, index: Int) -> Color {
        if set.completed {
            return Color.tempoRecoveryGreen
        } else if index == viewModel.currentSetIndex {
            return Color.tempoSignal
        } else {
            return Color.tempoTextTertiary.opacity(0.3)
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
                        .foregroundStyle(Color(red: 1, green: 215 / 255, blue: 0))

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
        // Per MODULE_TRAINING.md — sticky weight from previous set
        if let sticky = viewModel.stickyWeight {
            inputWeight = sticky
        }
        if let targetReps = viewModel.currentSet?.targetReps {
            inputReps = Double(targetReps)
        }
        inputRPE = nil
    }
}
