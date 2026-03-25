import SwiftUI
import SwiftData

// MARK: - Today's Workout View
// Per MODULE_TRAINING.md Section 2 — Launch pad for every training session.
// Per WIREFRAMES.md Section 3 — Training screens.

struct TodayWorkoutView: View {

    @Bindable var viewModel: TrainingViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TempoSpacing.xl) {
                    if viewModel.isLoading {
                        loadingState
                    } else if viewModel.isRestDay {
                        restDayContent
                    } else if let plan = viewModel.todayPlan {
                        workoutContent(plan: plan)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, 120) // space for floating button
            }
            .background(Color.tempoBgPrimary)

            // Floating Start Workout button
            if !viewModel.isRestDay && viewModel.todayPlan != nil && !viewModel.isLoading {
                startWorkoutButton
            }
        }
        .task {
            await viewModel.loadToday(modelContext: modelContext)
        }
    }

    // MARK: - Workout Content

    private func workoutContent(plan: WorkoutPlan) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            // Workout type header
            workoutHeader(plan: plan)

            // Recovery badge bar
            // Per MODULE_TRAINING.md Section 2.5
            recoveryBadge(plan: plan)

            // Workout meta bar
            // Per MODULE_TRAINING.md Section 2.6
            workoutMeta(plan: plan)

            // Exercise list
            // Per MODULE_TRAINING.md Section 2.7
            exerciseList(plan: plan)
        }
    }

    // MARK: - Workout Header

    private func workoutHeader(plan: WorkoutPlan) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            Text(plan.type.displayName.uppercased() + " DAY")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .padding(.top, TempoSpacing.md)
    }

    // MARK: - Recovery Badge
    // Per MODULE_TRAINING.md Section 2.5

    private func recoveryBadge(plan: WorkoutPlan) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Circle()
                .fill(recoveryDotColor(plan: plan))
                .frame(width: 10, height: 10)

            Text(recoveryText(plan: plan))
                .font(.tempoBody)
                .fontWeight(.medium)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("·")
                .foregroundStyle(Color.tempoTextTertiary)

            Text(adjustmentLabel(plan: plan))
                .font(.tempoBody)
                .foregroundStyle(recoveryDotColor(plan: plan))

            Spacer()
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Workout Meta
    // Per MODULE_TRAINING.md Section 2.6

    private func workoutMeta(plan: WorkoutPlan) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.xxs) {
                Image(systemName: "timer")
                    .font(.tempoCaption1)
                Text("~\(plan.durationMinutes ?? estimatedDuration(plan: plan)) min")
                    .font(.tempoCaption1)
            }
            .foregroundStyle(Color.tempoTextSecondary)

            Text("·")
                .foregroundStyle(Color.tempoTextTertiary)

            Text("\(plan.orderedExercises.count) exercises")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            Text("·")
                .foregroundStyle(Color.tempoTextTertiary)

            Text("\(plan.totalSets) sets")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    // MARK: - Exercise List
    // Per MODULE_TRAINING.md Section 2.7

    private func exerciseList(plan: WorkoutPlan) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            ForEach(Array(plan.orderedExercises.enumerated()), id: \.element.id) { index, plannedEx in
                exerciseCard(index: index + 1, plannedExercise: plannedEx)
            }
        }
    }

    private func exerciseCard(index: Int, plannedExercise: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            // Row 1: Number + Name + Muscle group
            HStack {
                Text("\(index)")
                    .font(.tempoCaption1)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(width: 20, alignment: .leading)

                Text(plannedExercise.exercise?.name.uppercased() ?? "EXERCISE")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)

                Spacer()

                if let muscleGroup = plannedExercise.exercise?.muscleGroup {
                    Text(muscleGroup.displayName.uppercased())
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .padding(.horizontal, TempoSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.tempoBgSecondary)
                        .clipShape(Capsule())
                }
            }

            // Row 2: Sets x Reps @ Weight
            if let sets = plannedExercise.sets, let firstSet = sets.first {
                HStack(spacing: TempoSpacing.xxs) {
                    Text(prescriptionText(sets: sets, firstSet: firstSet))
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)

                    // Progressive overload indicator
                    if let notes = plannedExercise.workoutPlan?.notes,
                       notes.contains("Increased") {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.tempoSignal)
                    }
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Start Workout Button
    // Per MODULE_TRAINING.md Section 2.9

    private var startWorkoutButton: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 20)
                .blur(radius: 10)

            Button {
                viewModel.startWorkout()
            } label: {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15))
                    Text("START WORKOUT")
                        .font(.tempoHeadline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.tempoSignal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.md)
        }
        .background(Color.tempoBgPrimary.opacity(0.95))
    }

    // MARK: - Rest Day Content
    // Per MODULE_TRAINING.md Section 2.10

    private var restDayContent: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer().frame(height: TempoSpacing.xxxl)

            Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            Text("REST DAY")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)

            Image(systemName: "figure.yoga")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoTextTertiary)

            VStack(spacing: TempoSpacing.sm) {
                Text("Your body builds muscle while you rest.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)

                if let nextType = nextWorkoutType {
                    VStack(spacing: TempoSpacing.xxs) {
                        Text("Next workout: Tomorrow")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text(nextType.uppercased())
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                }
            }

            // Mobility flow button
            Button {
                // Navigate to mobility session
            } label: {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "figure.flexibility")
                    Text("Start a Mobility Flow")
                }
                .font(.tempoHeadline)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.tempoSurfaceCard)
                .foregroundStyle(Color.tempoTextPrimary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            }
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: TempoSpacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Generating your workout...")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.lg) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 48))
                .foregroundStyle(Color.tempoTextTertiary)

            Text("No workout planned")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextSecondary)

            Button("Generate Today's Workout") {
                Task {
                    await viewModel.loadToday(modelContext: modelContext)
                }
            }
            .buttonStyle(.tempoPrimary)
        }
        .padding(.top, 100)
    }

    // MARK: - Helpers

    private func recoveryDotColor(plan: WorkoutPlan) -> Color {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 { return Color.tempoRecoveryGreen }
        if adj >= 0.6 { return Color.tempoRecoveryYellow }
        return Color.tempoRecoveryRed
    }

    private func recoveryText(plan: WorkoutPlan) -> String {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 { return "Green Recovery" }
        if adj >= 0.6 { return "Yellow Recovery" }
        return "Red Recovery"
    }

    private func adjustmentLabel(plan: WorkoutPlan) -> String {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 { return "Full Volume" }
        if adj >= 0.8 { return "-20% Volume" }
        if adj >= 0.75 { return "-20% Volume, Lighter Load" }
        return "Swapped to Mobility"
    }

    private func estimatedDuration(plan: WorkoutPlan) -> Int {
        let exercises = plan.orderedExercises
        let totalSets = exercises.reduce(0) { $0 + ($1.sets?.count ?? 0) }
        // ~2 min per set (including rest)
        return max(20, totalSets * 2 + exercises.count * 2)
    }

    private func prescriptionText(sets: [PlannedSet], firstSet: PlannedSet) -> String {
        let setCount = sets.count
        let reps = firstSet.targetReps
        if let weight = firstSet.targetWeight, weight > 0 {
            return "\(setCount) x \(reps) @ \(Int(weight))kg"
        }
        return "\(setCount) x \(reps) (BW)"
    }

    private var nextWorkoutType: String? {
        // Look at tomorrow's plan in weekPlans if loaded
        viewModel.weekPlans
            .first { Calendar.current.isDateInTomorrow($0.date) }
            .map { $0.type.displayName }
    }
}
