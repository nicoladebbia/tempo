//
// ExerciseLibraryView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Exercise Library View

// Per MODULE_TRAINING.md Section 10 — Exercise library with search and filters.
// Per WIREFRAMES.md Screen 19 — Search + filter chips + grouped list.

struct ExerciseLibraryView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query(sort: \Exercise.name)
    private var allExercises: [Exercise]

    @State
    private var searchText = ""
    @State
    private var selectedMuscleGroup: MuscleGroup?
    @State
    private var selectedEquipment: Equipment?

    /// Per UX_COPY_BIBLE.md Section 4.8
    private let muscleGroupFilters: [MuscleGroup] = [
        .chest, .back, .shoulders, .biceps, .triceps,
        .quads, .hamstrings, .glutes, .calves, .core, .cardio,
    ]

    private let equipmentFilters: [Equipment] = [
        .barbell, .dumbbell, .cable, .machine, .bodyweight, .kettlebell, .resistanceBand,
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.md) {
                // Search bar
                // Per MODULE_TRAINING.md Section 10.2 — real-time search
                searchBar

                // Muscle group filter chips
                // Per WIREFRAMES.md Screen 19 — horizontal scroll filter chips
                muscleGroupChips

                // Equipment filter chips
                equipmentChips

                // Results
                if filteredExercises.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
            }
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Search Bar

    // Per MODULE_TRAINING.md Section 10.2 — 44pt search bar

    private var searchBar: some View {
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextTertiary)

            TextField("Search exercises...", text: $searchText)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
        }
        .padding(.horizontal, TempoSpacing.md)
        .frame(height: 44)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.sm)
    }

    // MARK: - Muscle Group Chips

    // Per WIREFRAMES.md Screen 19 — horizontal scrollable filter chips, 24pt height

    private var muscleGroupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TempoSpacing.xs) {
                // "All" chip
                filterChip(label: "All", isSelected: selectedMuscleGroup == nil) {
                    selectedMuscleGroup = nil
                }

                ForEach(muscleGroupFilters, id: \.self) { group in
                    filterChip(label: group.displayName, isSelected: selectedMuscleGroup == group) {
                        selectedMuscleGroup = selectedMuscleGroup == group ? nil : group
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
        }
    }

    // MARK: - Equipment Chips

    private var equipmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TempoSpacing.xs) {
                filterChip(label: "All", isSelected: selectedEquipment == nil) {
                    selectedEquipment = nil
                }

                ForEach(equipmentFilters, id: \.self) { equip in
                    filterChip(label: equipmentLabel(equip), isSelected: selectedEquipment == equip) {
                        selectedEquipment = selectedEquipment == equip ? nil : equip
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        // Haptic parity with every other toggleable chip in the app (RPE
        // buttons, emphasis chips) — these were the only silent ones.
        Button {
            HapticManager.selection()
            action()
        } label: {
            Text(label)
                .font(.tempoCaption1)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : Color.tempoTextSecondary)
                .padding(.horizontal, TempoSpacing.sm)
                .frame(height: 28)
                .background(isSelected ? Color.tempoSignal : Color.tempoSurfaceCard)
                .clipShape(Capsule())
        }
    }

    // MARK: - Exercise List

    // Per MODULE_TRAINING.md Section 10.1 — grouped by muscle group with count

    private var exerciseList: some View {
        let grouped = groupedExercises
        return LazyVStack(spacing: TempoSpacing.xs, pinnedViews: [.sectionHeaders]) {
            ForEach(grouped.keys.sorted(by: { $0.displayName < $1.displayName }), id: \.self) { group in
                Section {
                    ForEach(grouped[group] ?? [], id: \.id) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            exerciseRow(exercise)
                        }
                    }
                } header: {
                    sectionHeader(group: group, count: grouped[group]?.count ?? 0)
                }
            }
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    private func sectionHeader(group: MuscleGroup, count: Int) -> some View {
        HStack {
            Text("\(group.displayName.uppercased()) (\(count))")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)

            Spacer()
        }
        .padding(.vertical, TempoSpacing.xs)
        .padding(.horizontal, TempoSpacing.xs)
        .background(Color.tempoBgPrimary)
    }

    /// Per WIREFRAMES.md Screen 19 — exercise row: name, muscle group pill, equipment + compound/isolation
    private func exerciseRow(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            HStack {
                Text(exercise.name.uppercased())
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)

                Spacer()

                Text(exercise.muscleGroup.displayName)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .padding(.horizontal, TempoSpacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.tempoSurfaceElevated)
                    .clipShape(Capsule())
            }

            HStack(spacing: TempoSpacing.xs) {
                Text(equipmentLabel(exercise.equipment))
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)

                Text("·")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)

                Text(exercise.isCompound ? "Compound" : "Isolation")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .padding(TempoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Empty State

    // Per WIREFRAMES.md Screen 71 State B — No results

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.md) {
            Spacer().frame(height: 80)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.tempoTextTertiary)

            Text("No exercises found.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)

            if !searchText.isEmpty {
                Text("Try a different search term.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Filtered Data

    private var filteredExercises: [Exercise] {
        var results = allExercises

        // Muscle group filter
        if let group = selectedMuscleGroup {
            results = results.filter { $0.muscleGroup == group }
        }

        // Equipment filter
        if let equip = selectedEquipment {
            results = results.filter { $0.equipment == equip }
        }

        // Search filter
        // Per MODULE_TRAINING.md Section 10.2 — searches name, muscle group, equipment
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter { exercise in
                exercise.name.lowercased().contains(query)
                    || exercise.muscleGroup.displayName.lowercased().contains(query)
                    || exercise.equipment.rawValue.lowercased().contains(query)
            }
        }

        return results
    }

    private var groupedExercises: [MuscleGroup: [Exercise]] {
        Dictionary(grouping: filteredExercises, by: \.muscleGroup)
    }

    // MARK: - Helpers

    private func equipmentLabel(_ equipment: Equipment) -> String {
        switch equipment {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .cable: "Cable"
        case .machine: "Machine"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .resistanceBand: "Band"
        case .smithMachine: "Smith"
        case .ezBar: "EZ Bar"
        case .trapBar: "Trap Bar"
        case .pullUpBar: "Pull-Up Bar"
        case .bench: "Bench"
        case .none: "None"
        }
    }
}
