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
    /// §10.6 — custom exercise creation sheet.
    @State
    private var showCreateExercise = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateExercise = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateExercise) {
            CustomExerciseFormView()
        }
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

                if exercise.isCustom {
                    Text("CUSTOM")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoSignal)
                        .padding(.horizontal, TempoSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.tempoSignal.opacity(0.12))
                        .clipShape(Capsule())
                }

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

// MARK: - CustomExerciseFormView (§10.6)

/// Create a custom exercise. Once saved it's a first-class library citizen:
/// it appears in search/filters (CUSTOM badge), the add-exercise and swap
/// pickers, and the engine's group-based selection can programme it. Delete
/// lives on the exercise's detail screen (custom exercises only).
struct CustomExerciseFormView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Query
    private var allExercises: [Exercise]

    @State
    private var name = ""
    @State
    private var muscleGroup: MuscleGroup = .chest
    @State
    private var equipment: Equipment = .barbell
    @State
    private var movementPattern: MovementPattern = .isolation
    @State
    private var isCompound = false
    @State
    private var instructions = ""
    @State
    private var cue = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Case-insensitive name collision with anything already in the library.
    private var isDuplicate: Bool {
        allExercises.contains { $0.name.compare(trimmedName, options: .caseInsensitive) == .orderedSame }
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isDuplicate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Landmine Press", text: $name)
                    if isDuplicate {
                        Text("An exercise with this name already exists.")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoWarning)
                    }
                }

                Section("Classification") {
                    Picker("Muscle group", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases, id: \.self) { group in
                            Text(group.displayName).tag(group)
                        }
                    }
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases, id: \.self) { eq in
                            Text(Self.equipmentLabel(eq)).tag(eq)
                        }
                    }
                    Picker("Movement pattern", selection: $movementPattern) {
                        ForEach(MovementPattern.allCases, id: \.self) { pattern in
                            Text(Self.patternLabel(pattern)).tag(pattern)
                        }
                    }
                    Toggle("Compound (multi-joint)", isOn: $isCompound)
                }

                Section {
                    TextField("How to perform it", text: $instructions, axis: .vertical)
                        .lineLimit(3 ... 6)
                    TextField("One-line coaching cue", text: $cue)
                } header: {
                    Text("Guidance (optional)")
                } footer: {
                    Text("Compound exercises get a warm-up ramp and 8-rep prescriptions; isolations get 12 reps.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let exercise = Exercise(
            name: trimmedName,
            muscleGroup: muscleGroup,
            equipment: equipment,
            movementPattern: movementPattern,
            isCompound: isCompound,
            isCustom: true,
            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : instructions.trimmingCharacters(in: .whitespacesAndNewlines),
            cues: cue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [] : [cue.trimmingCharacters(in: .whitespacesAndNewlines)]
        )
        modelContext.insert(exercise)
        try? modelContext.save()
        HapticManager.notification(.success)
        dismiss()
    }

    static func equipmentLabel(_ equipment: Equipment) -> String {
        switch equipment {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .cable: "Cable"
        case .machine: "Machine"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .resistanceBand: "Band"
        case .smithMachine: "Smith Machine"
        case .ezBar: "EZ Bar"
        case .trapBar: "Trap Bar"
        case .pullUpBar: "Pull-Up Bar"
        case .bench: "Bench"
        case .none: "None"
        }
    }

    static func patternLabel(_ pattern: MovementPattern) -> String {
        pattern.rawValue
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
