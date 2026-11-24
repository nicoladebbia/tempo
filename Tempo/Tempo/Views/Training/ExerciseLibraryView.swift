//
// ExerciseLibraryView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - ExerciseLibraryView

// Per MODULE_TRAINING.md Section 10 — Exercise library with search and filters.
// Per WIREFRAMES.md Screen 19 — Search + filter chips + grouped list.

struct ExerciseLibraryView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query(sort: \Exercise.name)
    private var allExercises: [Exercise]

    @Query
    private var userSettings: [UserSettings]

    @Environment(\.dynamicTypeSize)
    private var typeSize
    @State
    private var searchText = ""
    @State
    private var selectedMuscleGroup: MuscleGroup?
    @State
    private var selectedEquipment: Equipment?
    /// §10.6 — custom exercise creation sheet.
    @State
    private var showCreateExercise = false

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    /// Best estimated 1RM (display unit) across a lift's history, nil if none.
    private func bestE1RM(_ exercise: Exercise) -> String? {
        let best = (exercise.history ?? []).compactMap(\.estimated1RM).max()
        guard let best, best > 0 else {
            return nil
        }
        return WeightFormat.text(kg: best, unit: weightUnit)
    }

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
            VStack(spacing: Tide.s3) {
                // Search bar
                // Per MODULE_TRAINING.md Section 10.2 — real-time search
                searchBar

                // Muscle group filter chips
                // Per WIREFRAMES.md Screen 19 — horizontal scroll filter chips
                muscleGroupChips

                // Equipment filter chips
                equipmentChips

                // §11.9 — your most-trained lifts, one tap away. Only on the
                // unfiltered view: a filter/search means you're hunting.
                if searchText.isEmpty, selectedMuscleGroup == nil, selectedEquipment == nil {
                    mostTrainedStrip
                }

                // Results
                if filteredExercises.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
            }
            .padding(.top, Tide.s2)
            .padding(.bottom, TideTrain.pageBottom)
        }
        .tidePage()
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
        TrainPlanSearchField(text: $searchText, prompt: "Search exercises...")
            .padding(.horizontal, Tide.edge)
    }

    // MARK: - Muscle Group Chips

    // Per WIREFRAMES.md Screen 19 — horizontal scrollable filter chips, 24pt height

    private var muscleGroupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tide.s2) {
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
            .padding(.horizontal, Tide.edge)
        }
    }

    // MARK: - Equipment Chips

    private var equipmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tide.s2) {
                filterChip(label: "All", isSelected: selectedEquipment == nil) {
                    selectedEquipment = nil
                }

                ForEach(equipmentFilters, id: \.self) { equip in
                    filterChip(label: equipmentLabel(equip), isSelected: selectedEquipment == equip) {
                        selectedEquipment = selectedEquipment == equip ? nil : equip
                    }
                }
            }
            .padding(.horizontal, Tide.edge)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        TrainFilterChip(label: label, isSelected: isSelected, action: action)
    }

    // MARK: - Most Trained Strip (§11.9)

    @ViewBuilder
    private var mostTrainedStrip: some View {
        let top = allExercises
            .filter { !($0.history?.isEmpty ?? true) }
            .sorted { ($0.history?.count ?? 0) > ($1.history?.count ?? 0) }
            .prefix(6)
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s1) {
                TideSectionLabel(title: "Most trained")
                    .padding(.horizontal, Tide.edge)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tide.s2) {
                        ForEach(Array(top), id: \.id) { exercise in
                            NavigationLink {
                                ExerciseDetailView(exercise: exercise)
                            } label: {
                                VStack(alignment: .leading, spacing: Tide.hair) {
                                    Text(exercise.name)
                                        .accessibilityLabel(exercise.name.uppercased())
                                        .font(Tide.caption.weight(.semibold))
                                        .foregroundStyle(Tide.text)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(spacing: Tide.hair) {
                                        if let best = bestE1RM(exercise) {
                                            Text(best)
                                                .font(TideTrain.figure(.footnote, weight: .semibold))
                                                .foregroundStyle(Color.accentColor)
                                        }
                                        Text("· \(exercise.history?.count ?? 0)×")
                                            .font(Tide.caption)
                                            .foregroundStyle(Tide.text3)
                                    }
                                }
                                .frame(minWidth: TideTrain.statColumn, alignment: .leading)
                                .frame(minHeight: Tide.hit, alignment: .leading)
                                .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
                            }
                            .buttonStyle(.trainCard)
                        }
                    }
                    .padding(.horizontal, Tide.edge)
                }
            }
        }
    }

    // MARK: - Exercise List

    // Per MODULE_TRAINING.md Section 10.1 — grouped by muscle group with count

    private var exerciseList: some View {
        let grouped = groupedExercises
        return LazyVStack(spacing: Tide.s2, pinnedViews: [.sectionHeaders]) {
            ForEach(grouped.keys.sorted(by: { $0.displayName < $1.displayName }), id: \.self) { group in
                Section {
                    ForEach(grouped[group] ?? [], id: \.id) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            exerciseRow(exercise)
                        }
                        .buttonStyle(.trainCard)
                    }
                } header: {
                    sectionHeader(group: group, count: grouped[group]?.count ?? 0)
                }
            }
        }
        .padding(.horizontal, Tide.edge)
    }

    private func sectionHeader(group: MuscleGroup, count: Int) -> some View {
        HStack {
            Text(group.displayName).tideLabel()
            Spacer()
            Text("\(count)").tideLabel(Tide.text3)
        }
        .padding(.top, Tide.s3)
        .padding(.bottom, Tide.s1)
        .padding(.horizontal, Tide.s1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// §11.9 — row: demo thumb, name, equipment/type line, and YOUR numbers
    /// (best e1RM + times trained) when the lift has history.
    private func exerciseRow(_ exercise: Exercise) -> some View {
        let large = typeSize.isAccessibilitySize
        let details = VStack(alignment: .leading, spacing: Tide.hair) {
            Text(exercise.name)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if exercise.isCustom {
                Text("Custom").tideLabel(Color.accentColor)
                    .padding(.horizontal, Tide.s1)
                    .padding(.vertical, Tide.hair)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text("\(equipmentLabel(exercise.equipment)) · \(exercise.isCompound ? "Compound" : "Isolation")")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        let best = bestE1RM(exercise)
        let trained = Text("\(exercise.history?.count ?? 0)× trained")
            .font(Tide.caption)
            .foregroundStyle(Tide.text3)
            .multilineTextAlignment(.trailing)
        return Group {
            if large {
                // Large text: the picture and name on top, the best lift under them.
                VStack(alignment: .leading, spacing: Tide.s2) {
                    HStack(alignment: .top, spacing: Tide.s3) {
                        ExerciseImageView(exercise: exercise, style: .thumbnail)
                        details
                        Spacer(minLength: 0)
                    }
                    if let best {
                        HStack(spacing: Tide.s2) {
                            Text(best)
                                .font(TideTrain.figure(.footnote, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            trained
                        }
                    }
                }
            } else {
                HStack(spacing: Tide.s3) {
                    ExerciseImageView(exercise: exercise, style: .thumbnail)

                    details

                    Spacer(minLength: Tide.s1)

                    if let best {
                        VStack(alignment: .trailing, spacing: Tide.hair) {
                            Text(best)
                                .font(TideTrain.figure(.footnote, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            trained
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
    }

    // MARK: - Empty State

    // Per WIREFRAMES.md Screen 71 State B — No results

    private var emptyState: some View {
        TrainEmptyCard(
            systemImage: "magnifyingglass",
            title: "No exercises found.",
            message: searchText.isEmpty ? nil : "Try a different search term."
        )
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s4)
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

// MARK: - CustomExerciseFormView

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
            TrainPlanPage {
                TrainPlanField(label: "Name") {
                    TextField("e.g. Landmine Press", text: $name)
                }
                if isDuplicate {
                    Text("An exercise with this name already exists.")
                        .font(Tide.caption)
                        .foregroundStyle(TideTrain.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                TrainPlanCard(label: "Classification") {
                    TrainPlanPickerRow(title: "Muscle group", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases, id: \.self) { group in
                            Text(group.displayName).tag(group)
                        }
                    }
                    TrainPlanDivider()
                    TrainPlanPickerRow(title: "Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases, id: \.self) { eq in
                            Text(Self.equipmentLabel(eq)).tag(eq)
                        }
                    }
                    TrainPlanDivider()
                    TrainPlanPickerRow(title: "Movement pattern", selection: $movementPattern) {
                        ForEach(MovementPattern.allCases, id: \.self) { pattern in
                            Text(Self.patternLabel(pattern)).tag(pattern)
                        }
                    }
                    TrainPlanDivider()
                    TrainPlanToggleRow(title: "Compound (multi-joint)", isOn: $isCompound)
                }

                TrainPlanCard(label: "Guidance (optional)") {
                    TextField("How to perform it", text: $instructions, axis: .vertical)
                        .lineLimit(3 ... 6)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .tideFieldSurface()
                    TextField("One-line coaching cue", text: $cue)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .tideFieldSurface()
                    Text("Compound exercises get a warm-up ramp and 8-rep prescriptions; isolations get 12 reps.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .trainSheetRoot()
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
        modelContext.saveOrAlert("custom exercise")
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
