//
// RoutinesView.swift
// Tempo
//
// "My Routines": the athlete's own programs. List (use today / edit /
// delete), editor (name, lifts, working sets, group with next), and a
// library picker. Loads are never stored — applying re-prescribes them.
//

import SwiftData
import SwiftUI

// MARK: - RoutinesView

struct RoutinesView: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Query(sort: \WorkoutRoutine.createdAt, order: .reverse)
    private var routines: [WorkoutRoutine]

    @State
    private var editing: WorkoutRoutine?
    @State
    private var creatingNew = false
    @State
    private var pendingApply: WorkoutRoutine?
    @State
    private var message: String?

    var body: some View {
        List {
            if let blocker = viewModel.routineBlocker(for: viewModel.todayPlan) {
                Text(blocker)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .listRowBackground(Color.clear)
            }

            if routines.isEmpty {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("No routines yet.")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                    Text(
                        "Build one here, or save today's workout from the Training tab. Tempo still sets the loads from your history and recovery."
                    )
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                }
                .listRowBackground(Tide.fill)
            }

            ForEach(routines) { routine in
                routineRow(routine)
                    .listRowBackground(Tide.fill)
                    .swipeActions {
                        Button(role: .destructive) {
                            modelContext.delete(routine)
                            modelContext.saveOrAlert("routine change")
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editing = routine
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Color.accentColor)
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .tidePage()
        .navigationTitle("My Routines")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creatingNew = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New routine")
            }
        }
        .sheet(item: $editing) { routine in
            RoutineEditorView(routine: routine)
        }
        .sheet(isPresented: $creatingNew) {
            RoutineEditorView(routine: nil)
        }
        .confirmationDialog(
            "Replace today's workout?",
            isPresented: Binding(get: { pendingApply != nil }, set: {
                if !$0 {
                    pendingApply = nil
                }
            }),
            titleVisibility: .visible,
            presenting: pendingApply
        ) { routine in
            Button("Run \(routine.name) today") {
                if viewModel.applyRoutine(routine, modelContext: modelContext) {
                    dismiss()
                } else {
                    message = "Couldn't load that routine — its exercises are no longer in your library."
                }
            }
        } message: { _ in
            Text("Today's planned exercises are swapped for this routine. Loads come from your history and today's recovery.")
        }
        .alert("Routine", isPresented: Binding(get: { message != nil }, set: {
            if !$0 {
                message = nil
            }
        })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func routineRow(_ routine: WorkoutRoutine) -> some View {
        HStack(spacing: Tide.s2) {
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(routine.name)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Text(routine.items.map(\.exerciseName).joined(separator: " · "))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(2)
                Text("\(routine.items.count) exercises · \(routine.items.reduce(0) { $0 + $1.workingSets }) sets")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
            Spacer()
            Button("Use today") {
                pendingApply = routine
            }
            .font(Tide.caption.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .disabled(viewModel.routineBlocker(for: viewModel.todayPlan) != nil)
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = routine }
    }
}

// MARK: - RoutineEditorView

struct RoutineEditorView: View {
    /// nil = create a new routine on save.
    let routine: WorkoutRoutine?
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var name = ""
    @State
    private var items: [RoutineItem] = []
    @State
    private var showPicker = false
    @State
    private var loaded = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !items.isEmpty
    }

    var body: some View {
        editorBody
            .persistenceAlert()
    }

    private var editorBody: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Routine name (e.g. Upper A)", text: $name)
                        .font(Tide.body)
                }
                .listRowBackground(Tide.fill)

                Section("Exercises") {
                    ForEach($items) { $item in
                        itemRow($item)
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { items.remove(atOffsets: $0) }

                    Button {
                        showPicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .listRowBackground(Tide.fill)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .trainSheetRoot()
            .environment(\.editMode, .constant(.active))
            .navigationTitle(routine == nil ? "New Routine" : "Edit Routine")
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
            .sheet(isPresented: $showPicker) {
                RoutineExercisePicker(excluded: Set(items.map(\.exerciseID))) { exercise in
                    items.append(RoutineItem(
                        exerciseID: exercise.id,
                        exerciseName: exercise.name,
                        workingSets: 3
                    ))
                }
            }
            .onAppear {
                guard !loaded else {
                    return
                }
                loaded = true
                name = routine?.name ?? ""
                items = routine?.items ?? []
            }
        }
    }

    private func itemRow(_ item: Binding<RoutineItem>) -> some View {
        let index = items.firstIndex { $0.id == item.wrappedValue.id } ?? 0
        let groupedWithNext = index + 1 < items.count
            && item.wrappedValue.group != nil
            && items[index + 1].group == item.wrappedValue.group
        return VStack(alignment: .leading, spacing: Tide.s1) {
            HStack {
                Text(item.wrappedValue.exerciseName)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                Spacer()
                Stepper(
                    "\(item.wrappedValue.workingSets) sets",
                    value: item.workingSets,
                    in: 1 ... 10
                )
                .font(Tide.caption)
                .fixedSize()
            }
            if index + 1 < items.count {
                Toggle(isOn: Binding(
                    get: { groupedWithNext },
                    set: { setGrouped($0, at: index) }
                )) {
                    Label("Superset with next", systemImage: "link")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                .tint(Color.accentColor)
            }
        }
    }

    /// Joins/splits item `index` and the one after it. Joining reuses an
    /// existing group so pairs grow into circuits.
    private func setGrouped(_ grouped: Bool, at index: Int) {
        guard index + 1 < items.count else {
            return
        }
        if grouped {
            let group = items[index].group ?? items[index + 1].group
                ?? ((items.compactMap(\.group).max() ?? 0) + 1)
            items[index].group = group
            items[index + 1].group = group
        } else {
            // Split after `index`: the tail of the run gets a fresh group
            // (or none if it's left alone).
            let old = items[index].group
            let fresh = (items.compactMap(\.group).max() ?? 0) + 1
            var i = index + 1
            while i < items.count, items[i].group == old {
                items[i].group = fresh
                i += 1
            }
            normalizeSingletons()
        }
    }

    /// A group with one member is just a straight set.
    private func normalizeSingletons() {
        let counts = Dictionary(grouping: items.compactMap(\.group), by: { $0 }).mapValues(\.count)
        for i in items.indices where items[i].group.map({ counts[$0] ?? 0 }) == 1 {
            items[i].group = nil
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        normalizeSingletons()
        if let routine {
            routine.name = trimmed
            routine.items = items
        } else {
            modelContext.insert(WorkoutRoutine(name: trimmed, items: items))
        }
        if modelContext.saveOrAlert("routine") {
            dismiss()
        }
    }
}

// MARK: - RoutineExercisePicker

private struct RoutineExercisePicker: View {
    let excluded: Set<UUID>
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss)
    private var dismiss
    @Query(sort: \Exercise.name)
    private var allExercises: [Exercise]
    @State
    private var searchText = ""

    private var sections: [(group: MuscleGroup, exercises: [Exercise])] {
        let candidates = allExercises.filter {
            !excluded.contains($0.id)
                && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }
        return Dictionary(grouping: candidates, by: \.muscleGroup)
            .map { (group: $0.key, exercises: $0.value) }
            .sorted { $0.group.displayName < $1.group.displayName }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.group) { section in
                    Section(section.group.displayName) {
                        ForEach(section.exercises, id: \.id) { exercise in
                            Button {
                                onPick(exercise)
                                dismiss()
                            } label: {
                                ExercisePickRow(exercise: exercise)
                            }
                            .listRowBackground(Tide.fill)
                        }
                    }
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
