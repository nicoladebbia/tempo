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
    /// The Undo toast after a routine is deleted.
    @State
    private var toast: ToastData?

    var body: some View {
        List {
            if let blocker = viewModel.routineBlocker(for: viewModel.todayPlan) {
                // Why "Use today" is off, said once at the top as its own card.
                TrainBanner(
                    systemImage: "exclamationmark.circle.fill",
                    label: String(localized: "Not available today"),
                    tint: TideTrain.caution,
                    message: blocker
                ) {}
                    .trainPlanListRow()
            }

            if routines.isEmpty {
                TrainEmptyCard(
                    systemImage: "list.bullet.rectangle",
                    title: String(localized: "No routines yet."),
                    message: String(localized: "Build one here, or save today's workout from the Training tab. Tempo still sets the loads from your history and recovery.")
                )
                .trainPlanListRow()
            }

            ForEach(routines) { routine in
                routineRow(routine)
                    .trainPlanListRow()
                    .swipeActions {
                        Button(role: .destructive) {
                            delete(routine)
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, TideTrain.pageBottom, for: .scrollContent)
        .tidePage()
        .safeAreaBar(edge: .bottom) {
            // The way to make one, under the thumb: the lead action while the
            // list is empty, a quieter add row once there are routines.
            Group {
                if routines.isEmpty {
                    Button {
                        creatingNew = true
                    } label: {
                        Label("Build a routine", systemImage: "plus")
                    }
                    .buttonStyle(.tidePrimary)
                } else {
                    TrainPlanAddButton(title: String(localized: "New routine")) {
                        creatingNew = true
                    }
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s2)
        }
        .navigationTitle("My Routines")
        .firstTip(
            "train.routines",
            "A routine is a saved workout: build one here or save today's from the Training tab, and Tempo still sets the weights.",
            systemImage: "list.bullet.rectangle"
        )
        .tempoToast($toast, placement: .bottom)
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
                    message = String(localized: "Couldn't load that routine — its exercises are no longer in your library.")
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
        let blocked = viewModel.routineBlocker(for: viewModel.todayPlan) != nil
        let useButton = Button {
            pendingApply = routine
        } label: {
            Text("Use today")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.ink)
                .lineLimit(1)
                .padding(.horizontal, Tide.s4)
                .frame(minHeight: Tide.hit)
                .background(Color.accentColor, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .opacity(blocked ? 0.4 : 1)
        let setCount = routine.items.reduce(0) { $0 + $1.workingSets }
        let info = VStack(alignment: .leading, spacing: Tide.s2) {
            Text(routine.name)
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            // The size of it as two figures, like the day hero on Train.
            HStack(alignment: .firstTextBaseline, spacing: Tide.s4) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                    TideNumber("\(routine.items.count)", size: Tide.numeralS, relativeTo: .title3)
                    Text(TrainCount.noun(routine.items.count, "exercise"))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                    TideNumber("\(setCount)", size: Tide.numeralS, relativeTo: .title3)
                    Text(TrainCount.noun(setCount, "set"))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(TrainCount.text(routine.items.count, "exercise")) · \(TrainCount.text(setCount, "set"))")
            Text(routine.items.map(\.exerciseName).joined(separator: " · "))
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .lineLimit(2)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s3) {
                info
                Spacer(minLength: Tide.s2)
                useButton
            }
            VStack(alignment: .leading, spacing: Tide.s3) {
                info
                useButton
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .contentShape(.rect)
        .onTapGesture { editing = routine }
    }

    /// Deletes the routine and offers Undo for a few seconds. The routine is
    /// copied first and put back with the same id and date.
    private func delete(_ routine: WorkoutRoutine) {
        let snapshot = RoutineSnapshot(routine)
        modelContext.delete(routine)
        guard modelContext.saveOrAlert("routine change") else {
            return
        }
        toast = ToastData(message: String(localized: "Deleted \(snapshot.name)"), style: .info, actionTitle: String(localized: "Undo")) {
            snapshot.restore(in: modelContext)
            modelContext.saveOrAlert("routine change")
        }
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
    /// The Undo toast after an exercise is taken out of the routine.
    @State
    private var toast: ToastData?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !items.isEmpty
    }

    var body: some View {
        editorBody
            .tempoToast($toast, placement: .bottom)
            .persistenceAlert()
    }

    /// Takes the exercises out and offers Undo for a few seconds; Undo puts
    /// each back where it was. Nothing is saved until Save, so this only
    /// touches the editor's own list.
    private func removeItems(at offsets: IndexSet) {
        let removal = RoutineItemRemoval(offsets: offsets, in: items)
        guard !removal.isEmpty else {
            return
        }
        items.remove(atOffsets: offsets)
        toast = ToastData(message: removal.message, style: .info, actionTitle: String(localized: "Undo")) {
            withAnimation(Tide.snap) {
                removal.restore(into: &items)
            }
        }
    }

    private var editorBody: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Routine name (e.g. Upper A)", text: $name)
                        .font(Tide.body)
                        .tideFieldSurface()
                        // The grouped list already insets its rows, so the
                        // field lines up with the exercise group below it.
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    ForEach($items) { $item in
                        itemRow($item)
                            .listRowBackground(Tide.fill)
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { removeItems(at: $0) }

                    Button {
                        showPicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, minHeight: Tide.hit)
                            .contentShape(.rect)
                    }
                    .listRowBackground(Tide.fill)
                } header: {
                    TideSectionLabel(title: String(localized: "Exercises"))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .trainSheetRoot()
            .safeAreaBar(edge: .bottom) {
                // Save under the thumb, and say what is still missing while it is off.
                VStack(spacing: Tide.s2) {
                    if !canSave {
                        Text("Name it and add an exercise.")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                    Button {
                        save()
                    } label: {
                        Text("Save routine")
                    }
                    .buttonStyle(.tidePrimary)
                    .disabled(!canSave)
                }
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s2)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(routine == nil ? String(localized: "New Routine") : String(localized: "Edit Routine"))
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
        let title = Text(item.wrappedValue.exerciseName)
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.text)
        let stepper = Stepper(
            TrainCount.text(item.wrappedValue.workingSets, "set"),
            value: item.workingSets,
            in: 1 ... 10
        )
        .font(Tide.caption)
        .fixedSize()
        return VStack(alignment: .leading, spacing: Tide.s1) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s2) {
                    title
                        .lineLimit(2)
                    Spacer(minLength: Tide.s2)
                    stepper
                }
                VStack(alignment: .leading, spacing: Tide.s1) {
                    title
                    stepper
                }
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
                .frame(minHeight: Tide.hit)
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
