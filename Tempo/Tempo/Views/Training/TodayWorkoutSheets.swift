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

// MARK: - Picker row layout

private extension View {
    /// A list row that reads as a Tide card: no separator, no row fill, a
    /// small gap between neighbours. The card itself is drawn by the caller.
    func trainPickerRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: Tide.s1, leading: Tide.edge, bottom: Tide.s1, trailing: Tide.edge))
    }
}

// MARK: - ExerciseReorderSheet

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
                let exercises = viewModel.todayPlan?.orderedExercises ?? []
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, ex in
                    HStack(spacing: Tide.s3) {
                        Text("\(index + 1)")
                            .font(TideTrain.figure(.headline))
                            .foregroundStyle(Tide.text3)
                            .frame(minWidth: Tide.s5, alignment: .leading)
                        Text(ex.exercise?.name ?? "Exercise")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Tide.s2)
                        if ex.supersetGroup != nil {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(Tide.label)
                                .foregroundStyle(Color.accentColor)
                                .accessibilityLabel("Superset")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
                    .trainPickerRow()
                }
                .onMove { source, destination in
                    viewModel.moveExercises(from: source, to: destination)
                    modelContext.saveOrAlert("exercise order")
                    HapticManager.selection()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .trainSheetRoot()
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

// MARK: - SwapExerciseSheet

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
                    TrainEmptyCard(
                        systemImage: "arrow.triangle.swap",
                        title: "No alternatives for this muscle group."
                    )
                    .trainPickerRow()
                } else {
                    ForEach(alternatives, id: \.id) { exercise in
                        Button {
                            viewModel.swapExercise(target, with: exercise, modelContext: modelContext)
                            dismiss()
                        } label: {
                            ExercisePickRow(exercise: exercise)
                                .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
                                .contentShape(.rect)
                        }
                        .buttonStyle(TideCardPressStyle())
                        .trainPickerRow()
                    }
                    // §2.13b — swaps teach the planner.
                    Text("Tempo remembers your pick — future days prescribe it instead. Swap back anytime to undo.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .trainPickerRow()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .trainSheetRoot()
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

// MARK: - AddExerciseSheet

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
                if sections.isEmpty {
                    TrainEmptyCard(
                        systemImage: "magnifyingglass",
                        title: "Nothing found",
                        message: "Try a different name."
                    )
                    .trainPickerRow()
                }
                ForEach(sections, id: \.group) { section in
                    Section {
                        ForEach(section.exercises, id: \.id) { exercise in
                            Button {
                                viewModel.addExercise(exercise, modelContext: modelContext)
                                dismiss()
                            } label: {
                                ExercisePickRow(exercise: exercise)
                                    .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(TideCardPressStyle())
                            .trainPickerRow()
                        }
                    } header: {
                        Text(section.group.displayName)
                            .tideLabel()
                            .padding(.top, Tide.s2)
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .trainSheetRoot()
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

// MARK: - ExercisePickRow

/// Shared row for the swap/add pickers: name + equipment, compound badge.
struct ExercisePickRow: View {
    let exercise: Exercise

    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var stacksTag: Bool {
        typeSize.isAccessibilitySize
    }

    var body: some View {
        HStack(spacing: Tide.s3) {
            ExerciseImageView(exercise: exercise, style: .thumbnail)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(exercise.name)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(exercise.equipment.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                if exercise.isCompound, stacksTag {
                    TrainTag(text: "Compound")
                        .padding(.top, Tide.s1)
                }
            }
            Spacer(minLength: Tide.s2)
            if exercise.isCompound, !stacksTag {
                TrainTag(text: "Compound")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
