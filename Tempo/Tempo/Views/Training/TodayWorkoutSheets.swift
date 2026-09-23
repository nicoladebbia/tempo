//
// TodayWorkoutSheets.swift
// Tempo
//
// Reorder / swap / add-exercise sheets presented from TodayWorkoutView.
// Split out of TodayWorkoutView.swift to keep it under the SwiftLint file
// length cap.
//

import SwiftData
import SwiftUI

// MARK: - ExerciseReorderSheet (§2.15)

/// Drag-to-reorder for today's planned exercises. A dedicated List because
/// `.onMove` is List-only — the styled card stack in TodayWorkoutView can't
/// host it. Order writes through `moveExercises` (which renumbers
/// `PlannedExercise.order`) and persists immediately; moving one member of a
/// superset out of adjacency deliberately splits that superset (grouping is
/// consecutive-run based).
struct ExerciseReorderSheet: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.todayPlan?.orderedExercises ?? [], id: \.id) { ex in
                    HStack(spacing: TempoSpacing.sm) {
                        Text(ex.exercise?.name ?? "Exercise")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        if ex.supersetGroup != nil {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.tempoSignal)
                        }
                    }
                    .listRowBackground(Color.tempoSurfaceCard)
                }
                .onMove { source, destination in
                    viewModel.moveExercises(from: source, to: destination)
                    try? modelContext.save()
                    HapticManager.selection()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - SwapExerciseSheet (§2.13)

/// Alternatives for one planned slot — same muscle group, closest movement
/// pattern first. Selecting one swaps the movement in place (order and
/// superset pairing kept, prescription rebuilt for the new lift).
struct SwapExerciseSheet: View {
    @Bindable
    var viewModel: TrainingViewModel
    let target: PlannedExercise
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let alternatives = viewModel.swapAlternatives(for: target, modelContext: modelContext)
                if alternatives.isEmpty {
                    Text("No alternatives for this muscle group.")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .listRowBackground(Color.tempoSurfaceCard)
                } else {
                    ForEach(alternatives, id: \.id) { exercise in
                        Button {
                            viewModel.swapExercise(target, with: exercise, modelContext: modelContext)
                            dismiss()
                        } label: {
                            ExercisePickRow(exercise: exercise)
                        }
                        .listRowBackground(Color.tempoSurfaceCard)
                    }
                    // §2.13b — swaps teach the planner.
                    Text("Tempo remembers your pick — future days prescribe it instead. Swap back anytime to undo.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Swap \(target.exercise?.name ?? "Exercise")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - AddExerciseSheet (§2.14)

/// Full-library picker for appending an exercise to today's plan. Searchable,
/// sectioned by muscle group; movements already in the plan are excluded.
struct AddExerciseSheet: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Query(sort: \Exercise.name)
    private var allExercises: [Exercise]
    @State
    private var searchText = ""

    private var candidates: [Exercise] {
        let inPlan = Set(
            (viewModel.todayPlan?.orderedExercises ?? []).compactMap { $0.exercise?.id }
        )
        return allExercises.filter { exercise in
            guard !inPlan.contains(exercise.id) else {
                return false
            }
            guard !searchText.isEmpty else {
                return true
            }
            return exercise.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Muscle-group sections, ordered by group display name.
    private var sections: [(group: MuscleGroup, exercises: [Exercise])] {
        Dictionary(grouping: candidates, by: \.muscleGroup)
            .map { (group: $0.key, exercises: $0.value) }
            .sorted { $0.group.displayName < $1.group.displayName }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.group) { section in
                    Section(section.group.displayName.uppercased()) {
                        ForEach(section.exercises, id: \.id) { exercise in
                            Button {
                                viewModel.addExercise(exercise, modelContext: modelContext)
                                dismiss()
                            } label: {
                                ExercisePickRow(exercise: exercise)
                            }
                            .listRowBackground(Color.tempoSurfaceCard)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Shared row for the swap/add pickers: name + equipment, compound badge.
struct ExercisePickRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: TempoSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(exercise.equipment.rawValue.capitalized)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            Spacer()
            if exercise.isCompound {
                Text("COMPOUND")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .padding(.horizontal, TempoSpacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.tempoBgSecondary)
                    .clipShape(Capsule())
            }
        }
    }
}
