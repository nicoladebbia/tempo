//
// TrainerProgramReviewView.swift
// Tempo
//
// Edit-before-save for an imported Trainer Program: program name, start
// date, repeats, then per-week -> per-day (weekday/title/focus incl.
// conditioning/notes) -> per-exercise. A strength day edits sets/reps/
// weight/RPE/%1RM/rest/superset group/per-side/notes; a conditioning day
// (focus run/sprint/conditioning/pool/mobility) edits a free-text `detail`
// prescription instead of sets x reps. Two days can share a weekday (a lift
// + a conditioning session) — shown as "Lift + conditioning". Save resolves
// any still-unmatched exercise into a custom library entry
// (TrainerProgramSaver), deactivates any other active program, and posts
// `.tempoTrainingSettingsChanged` so the plan regenerates.
//

import SwiftData
import SwiftUI

// MARK: - TrainerProgramReviewView

struct TrainerProgramReviewView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(ServiceContainer.self)
    private var services
    @Query(sort: \Exercise.name)
    private var libraryExercises: [Exercise]
    @Query
    private var userSettings: [UserSettings]
    /// Fix #11(b) — to offer "starts after the current one ends" / "on a
    /// date" when importing a NEW program while one is already active.
    @Query
    private var allPrograms: [TrainerProgram]

    /// Fix #11(a) — non-nil means this screen is EDITING a saved program in
    /// place (`TrainerProgramSaver.update`) rather than reviewing a freshly
    /// parsed one before its first save.
    let editingProgram: TrainerProgram?
    let sourceKind: String
    let sourceText: String
    var onSaved: () -> Void

    /// Researched details for exercises the library doesn't have.
    @State
    private var research: ExerciseResearchStore

    @State
    private var name: String
    @State
    private var startDate: Date
    @State
    private var repeats = true
    /// §13 — whether Tempo adds its own 50%/75% ramp warm-ups on this
    /// program's lifting days. Defaults on (matches `TrainerProgram.
    /// warmupsEnabled`'s nil-means-true default for a brand-new program).
    @State
    private var autoWarmups = true
    /// Fix #6 — chosen here (and editable later on TrainerProgramView).
    @State
    private var scheduleMode: TrainerProgramScheduleMode = .fixed
    @State
    private var weeks: [ProgramWeek]
    @State
    private var autoAssignedWeekdays: Bool
    @State
    private var saveError: String?
    /// Weekday-less sessions are placed around football once, on appear
    /// (UserSettings isn't available at init). Skipped entirely when editing
    /// — an already-saved program's weekdays are deliberate, not a fresh
    /// auto-placement.
    @State
    private var didPlaceAroundFootball = false
    /// Fix #11(b) — when creating a NEW program while one is already active.
    @State
    private var startTiming: StartTiming = .now

    enum StartTiming: Hashable {
        case now
        case afterCurrent
        case onDate
    }

    /// Import flow (new program, nothing saved yet).
    init(
        parsed: TrainerProgramParser.ParsedProgram,
        sourceKind: String,
        sourceText: String,
        researchSessionID: String? = nil,
        onSaved: @escaping () -> Void
    ) {
        editingProgram = nil
        _research = State(initialValue: ExerciseResearchStore(importSessionID: researchSessionID))
        _name = State(initialValue: parsed.name)
        _startDate = State(initialValue: TrainingCalendar.mondayOfWeek(containing: Date()))
        _weeks = State(initialValue: parsed.weeks)
        _autoAssignedWeekdays = State(initialValue: parsed.autoAssignedWeekdays)
        self.sourceKind = sourceKind
        self.sourceText = sourceText
        self.onSaved = onSaved
    }

    /// Fix #11(a) — edit flow for an already-saved program.
    init(editingProgram program: TrainerProgram, onSaved: @escaping () -> Void) {
        editingProgram = program
        _research = State(initialValue: ExerciseResearchStore(importSessionID: nil))
        _name = State(initialValue: program.name)
        _startDate = State(initialValue: program.startDate)
        _repeats = State(initialValue: program.repeats)
        _autoWarmups = State(initialValue: program.warmupsEnabled)
        _scheduleMode = State(initialValue: program.scheduleMode)
        _weeks = State(initialValue: program.weeks)
        _autoAssignedWeekdays = State(initialValue: false)
        _didPlaceAroundFootball = State(initialValue: true) // never auto-place an edit
        sourceKind = program.sourceKind
        sourceText = program.sourceText ?? ""
        self.onSaved = onSaved
    }

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    private var isValid: Bool {
        !weeks.isEmpty && weeks.contains { $0.days.contains { !$0.exercises.isEmpty } }
    }

    /// The program THIS import would replace/queue behind — nil when
    /// editing (edits never re-queue) or nothing else is active.
    private var otherActiveProgram: TrainerProgram? {
        guard editingProgram == nil else {
            return nil
        }
        return allPrograms.first { $0.isActive }
    }

    var body: some View {
        reviewContent
            .environment(research)
            .task(id: unmatchedNames) {
                research.configure(provider: ExerciseResearchService(apiClient: services.apiClient))
                guard research.isAutomatic, let sessionID = research.sessionID, !unmatchedNames.isEmpty else {
                    return
                }
                // Debounce: the name fields re-fire this on every keystroke.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }
                await research.research(names: unmatchedNames, sessionID: sessionID)
            }
            .task {
                guard !didPlaceAroundFootball else {
                    return
                }
                didPlaceAroundFootball = true
                let football = ProgramScheduler.isoWeekdays(of: userSettings.first?.footballDays ?? ActiveDays(rawValue: 0))
                weeks = ProgramScheduler.place(weeks: weeks, footballWeekdays: football)
            }
    }

    private var reviewContent: some View {
        NavigationStack {
            Form {
                programSection
                if autoAssignedWeekdays {
                    Section {
                        Text("We placed these around your football — change any day.")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                ForEach($weeks) { $week in
                    WeekEditorSection(
                        week: $week,
                        weekNumber: (weeks.firstIndex(where: { $0.id == week.id }) ?? 0) + 1,
                        libraryExercises: libraryExercises,
                        weightUnit: weightUnit,
                        canRemoveWeek: weeks.count > 1,
                        onRemoveWeek: { removeWeek(week.id) }
                    )
                }
                Section {
                    Button {
                        addWeek()
                    } label: {
                        Label("Add Week", systemImage: "plus.circle")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .navigationTitle(editingProgram == nil ? "Review Program" : "Edit Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .alert(
                "Couldn't save",
                isPresented: Binding(get: { saveError != nil }, set: {
                    if !$0 {
                        saveError = nil
                    }
                })
            ) {
                Button("OK") {}
            } message: {
                Text(saveError ?? "")
            }
        }
        // See TrainerProgramImportView — matches the standalone-screen
        // convention for a modally-presented dark-only screen.
        .preferredColorScheme(.dark)
    }

    // MARK: - Program-level section

    private var programSection: some View {
        Section("PROGRAM") {
            TextField("Program name", text: $name)
                .font(.tempoBody)

            DatePicker(
                "Start date (Monday)",
                selection: Binding(
                    get: { startDate },
                    set: { startDate = TrainingCalendar.mondayOfWeek(containing: $0) }
                ),
                displayedComponents: .date
            )
            .disabled(startTiming == .afterCurrent)

            if weeks.count > 1 {
                Toggle("Repeats after last week", isOn: $repeats)
                    .tint(Color.tempoSignal)
            }

            Toggle(isOn: $autoWarmups) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tempo warm-up sets")
                    Text("Add a 50%/75% ramp before each lift. Off — exactly what your trainer wrote.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .tint(Color.tempoSignal)

            // Fix #6 — schedule mode, editable here and later on
            // TrainerProgramView.
            Picker("Schedule", selection: $scheduleMode) {
                ForEach(TrainerProgramScheduleMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Text(scheduleMode.explanation)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            // Fix #11(b) — queue behind the current program instead of
            // replacing it immediately.
            if let otherActiveProgram {
                Picker("Starts", selection: $startTiming) {
                    Text("Now — replaces \"\(otherActiveProgram.name)\"").tag(StartTiming.now)
                    if !otherActiveProgram.repeats {
                        Text("After \"\(otherActiveProgram.name)\" ends").tag(StartTiming.afterCurrent)
                    }
                    Text("On a date").tag(StartTiming.onDate)
                }
                .onChange(of: startTiming) { _, newValue in
                    switch newValue {
                    case .now:
                        break
                    case .afterCurrent:
                        if let end = blockEndDate(of: otherActiveProgram) {
                            startDate = TrainingCalendar.mondayOfWeek(containing: end)
                        }
                    case .onDate:
                        break
                    }
                }
                if startTiming != .now {
                    Text(queueExplanation)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        }
    }

    /// Monday of the week right after `program`'s last week — nil for a
    /// repeating (never-ending) program.
    private func blockEndDate(of program: TrainerProgram) -> Date? {
        guard !program.repeats else {
            return nil
        }
        return Calendar.current.date(byAdding: .day, value: program.weeks.count * 7, to: program.startDate)
    }

    private var queueExplanation: String {
        switch startTiming {
        case .now:
            ""
        case .afterCurrent:
            "Starts \(startDate.formatted(date: .abbreviated, time: .omitted)) — auto-activates that day; your current program keeps running until then."
        case .onDate:
            "Starts \(startDate.formatted(date: .abbreviated, time: .omitted)) — pick the date above. Your current program keeps running until then."
        }
    }

    // MARK: - Actions

    private func addWeek() {
        weeks.append(ProgramWeek(days: []))
    }

    private func removeWeek(_ id: UUID) {
        guard weeks.count > 1 else {
            return
        }
        weeks.removeAll { $0.id == id }
    }

    /// Strength-day exercise names with no library match (and not linked by
    /// hand) — the ones Save would create as new exercises.
    private var unmatchedNames: [String] {
        let known = Set(libraryExercises.map(\.id))
        let candidates = libraryExercises.map { ExerciseMatcher.Candidate(id: $0.id, name: $0.name) }
        var seen = Set<String>()
        var names: [String] = []
        for day in weeks.flatMap(\.days) where day.isStrength {
            for exercise in day.exercises {
                let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, seen.insert(ExerciseMatcher.normalize(name)).inserted else {
                    continue
                }
                if let id = exercise.exerciseID, known.contains(id) {
                    continue
                }
                if ExerciseMatcher.match(name, in: candidates) == nil {
                    names.append(name)
                }
            }
        }
        return names
    }

    private func save() {
        do {
            if let editingProgram {
                // Fix #11(a) — edit in place.
                try TrainerProgramSaver.update(
                    editingProgram,
                    name: name,
                    startDate: startDate,
                    weeks: weeks,
                    repeats: weeks.count > 1 ? repeats : true,
                    autoWarmups: autoWarmups,
                    scheduleMode: scheduleMode,
                    modelContext: modelContext,
                    trainingEngine: services.trainingEngine,
                    whoop: services.whoop,
                    healthKit: services.healthKit,
                    research: research.results
                )
            } else {
                let queuedActivationDate: Date? = startTiming == .now ? nil : startDate
                let saved = try TrainerProgramSaver.save(
                    name: name,
                    startDate: startDate,
                    weeks: weeks,
                    repeats: weeks.count > 1 ? repeats : true,
                    sourceKind: sourceKind,
                    sourceText: sourceText,
                    modelContext: modelContext,
                    autoWarmups: autoWarmups,
                    scheduleMode: scheduleMode,
                    research: research.results,
                    queuedActivationDate: queuedActivationDate
                )
                _ = saved
            }
            onSaved()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - WeekEditorSection

private struct WeekEditorSection: View {
    @Binding
    var week: ProgramWeek
    let weekNumber: Int
    let libraryExercises: [Exercise]
    let weightUnit: WeightUnit
    let canRemoveWeek: Bool
    let onRemoveWeek: () -> Void

    var body: some View {
        Section {
            ForEach($week.days) { $day in
                DayEditorView(
                    day: $day,
                    pairedSessionLabel: pairedSessionLabel(for: day),
                    libraryExercises: libraryExercises,
                    weightUnit: weightUnit,
                    onRemoveDay: { removeDay(day.id) }
                )
            }
            Button {
                addDay()
            } label: {
                Label("Add Day", systemImage: "plus")
            }
        } header: {
            HStack {
                Text("WEEK \(weekNumber)")
                Spacer()
                if canRemoveWeek {
                    Button("Remove", role: .destructive, action: onRemoveWeek)
                        .font(.tempoCaption2)
                }
            }
        }
    }

    /// Two sessions land on the same weekday when a trainer schedules a
    /// lift + a conditioning session on the same day — call that out rather
    /// than let it read as an accidental duplicate.
    private func pairedSessionLabel(for day: ProgramDay) -> String? {
        let sameWeekday = week.days.filter { $0.weekday == day.weekday }
        guard sameWeekday.count == 2 else {
            return nil
        }
        return "Lift + conditioning"
    }

    private func addDay() {
        let used = Set(week.days.map(\.weekday))
        let nextWeekday = (1 ... 7).first { !used.contains($0) } ?? 1
        week.days.append(ProgramDay(weekday: nextWeekday, title: nil, focus: nil, exercises: [], notes: nil))
    }

    private func removeDay(_ id: UUID) {
        week.days.removeAll { $0.id == id }
    }
}

// MARK: - DayEditorView

private struct DayEditorView: View {
    @Binding
    var day: ProgramDay
    /// "Lift + conditioning" when another day shares this weekday — nil
    /// otherwise.
    let pairedSessionLabel: String?
    let libraryExercises: [Exercise]
    let weightUnit: WeightUnit
    let onRemoveDay: () -> Void

    /// Every focus a trainer program can carry — strength and conditioning
    /// — excluding rest/football, which aren't sessions a program schedules.
    private static let focusTypes = WorkoutType.allCases.filter { $0 != .rest && $0 != .football }

    private var isConditioning: Bool {
        !day.isStrength
    }

    var body: some View {
        DisclosureGroup {
            Picker("Day", selection: $day.weekday) {
                ForEach(1 ... 7, id: \.self) { weekday in
                    Text(TrainerProgramView.shortWeekdayName(weekday)).tag(weekday)
                }
            }
            // The user chose this day — it's no longer an auto-placement.
            .onChange(of: day.weekday) { _, _ in
                day.weekdayGuessed = false
            }

            TextField("Day title (optional)", text: stringBinding(for: $day.title))

            Picker("Focus", selection: $day.focus) {
                Text("None").tag(String?.none)
                ForEach(Self.focusTypes, id: \.self) { type in
                    Text(type.displayName).tag(String?.some(type.rawValue))
                }
            }

            TextField("Day notes (optional)", text: stringBinding(for: $day.notes), axis: .vertical)

            ForEach($day.exercises) { $exercise in
                ExerciseRowEditor(
                    exercise: $exercise,
                    isConditioning: isConditioning,
                    libraryExercises: libraryExercises,
                    weightUnit: weightUnit,
                    canMoveUp: canMove(exercise.id, delta: -1),
                    canMoveDown: canMove(exercise.id, delta: 1),
                    onMoveUp: { move(exercise.id, by: -1) },
                    onMoveDown: { move(exercise.id, by: 1) },
                    onRemove: { removeExercise(exercise.id) }
                )
            }

            Button {
                addExercise()
            } label: {
                Label("Add Exercise", systemImage: "plus")
            }

            Button("Remove This Day", role: .destructive, action: onRemoveDay)
                .font(.tempoCaption1)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TempoSpacing.xs) {
                    Text("\(TrainerProgramView.shortWeekdayName(day.weekday)) — \(day.title ?? (day.workoutType.displayName))")
                        .font(.tempoBodyBold)
                        .foregroundStyle(Color.tempoTextPrimary)
                    if day.weekdayGuessed == true {
                        Image(systemName: "wand.and.stars")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoWarning)
                            .accessibilityLabel("Day auto-placed")
                    }
                }
                if let pairedSessionLabel {
                    Text(pairedSessionLabel)
                        .font(.tempoCaption2.weight(.semibold))
                        .foregroundStyle(Color.tempoSignal)
                }
                Text("\(day.exercises.count) exercise\(day.exercises.count == 1 ? "" : "s")")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
    }

    private func addExercise() {
        day.exercises.append(ProgramExercise(
            name: "",
            exerciseID: nil,
            sets: isConditioning ? 1 : 3,
            repsLow: isConditioning ? 1 : 10,
            repsHigh: nil,
            weightKg: nil,
            rpe: nil,
            percentOf1RM: nil,
            restSeconds: isConditioning ? nil : 90,
            group: nil,
            notes: nil,
            detail: isConditioning ? "" : nil
        ))
    }

    private func removeExercise(_ id: UUID) {
        day.exercises.removeAll { $0.id == id }
    }

    private func canMove(_ id: UUID, delta: Int) -> Bool {
        guard let index = day.exercises.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let target = index + delta
        return target >= 0 && target < day.exercises.count
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let index = day.exercises.firstIndex(where: { $0.id == id }) else {
            return
        }
        let target = index + delta
        guard target >= 0, target < day.exercises.count else {
            return
        }
        day.exercises.swapAt(index, target)
    }
}

// MARK: - ExerciseRowEditor

private struct ExerciseRowEditor: View {
    @Binding
    var exercise: ProgramExercise
    /// A conditioning day (run/sprint/conditioning/pool/mobility) edits a
    /// free-text `detail` prescription instead of sets x reps/weight/%1RM.
    let isConditioning: Bool
    let libraryExercises: [Exercise]
    let weightUnit: WeightUnit
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    @State
    private var showPicker = false
    @State
    private var showResearchEditor = false
    @Environment(ExerciseResearchStore.self)
    private var research

    /// `sets`/`repsLow` are non-optional Ints, but the text field needs to
    /// tolerate a transient empty string while the user backspaces to retype
    /// (e.g. "3" -> "" -> "5"). Binding straight to `exercise.sets`/`repsLow`
    /// would refuse to write on the empty intermediate state, so the field's
    /// text snaps back to the old value before a new digit can be typed. These
    /// local buffers are the field's actual source of truth; they only push a
    /// value into the model once it parses.
    @State
    private var setsText: String
    @State
    private var repsLowText: String

    init(
        exercise: Binding<ProgramExercise>,
        isConditioning: Bool,
        libraryExercises: [Exercise],
        weightUnit: WeightUnit,
        canMoveUp: Bool,
        canMoveDown: Bool,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        _exercise = exercise
        self.isConditioning = isConditioning
        self.libraryExercises = libraryExercises
        self.weightUnit = weightUnit
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onRemove = onRemove
        _setsText = State(initialValue: String(exercise.wrappedValue.sets))
        _repsLowText = State(initialValue: String(exercise.wrappedValue.repsLow))
    }

    private var candidates: [ExerciseMatcher.Candidate] {
        libraryExercises.map { .init(id: $0.id, name: $0.name) }
    }

    private var matchedExercise: Exercise? {
        guard let id = exercise.exerciseID else {
            return nil
        }
        return libraryExercises.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                TextField("Exercise name", text: $exercise.name)
                    .font(.tempoBodyBold)
                Spacer()
                Button {
                    onMoveUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                Button {
                    onMoveDown()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.borderless)

            matchIndicator

            if isConditioning {
                labeledField("Prescription") {
                    TextField("e.g. 35' — 2' slow / 1' fast / 30\" walk", text: stringBinding(for: $exercise.detail), axis: .vertical)
                        .lineLimit(2 ... 4)
                }
                HStack(spacing: TempoSpacing.md) {
                    labeledField("RPE") { TextField("rpe", text: stringBinding(for: $exercise.rpe)).keyboardType(.decimalPad) }
                    labeledField("Rest (sec)") {
                        TextField("rest", text: stringBinding(for: $exercise.restSeconds)).keyboardType(.numberPad)
                    }
                    labeledField("Superset #") { TextField("group", text: stringBinding(for: $exercise.group)).keyboardType(.numberPad) }
                }
            } else {
                HStack(spacing: TempoSpacing.md) {
                    labeledField("Sets") {
                        TextField("sets", text: $setsText)
                            .keyboardType(.numberPad)
                            .onChange(of: setsText) { _, newValue in
                                if let parsed = Int(newValue), parsed > 0 {
                                    exercise.sets = parsed
                                }
                            }
                    }
                    labeledField("Reps low") {
                        TextField("low", text: $repsLowText)
                            .keyboardType(.numberPad)
                            .onChange(of: repsLowText) { _, newValue in
                                if let parsed = Int(newValue), parsed > 0 {
                                    exercise.repsLow = parsed
                                }
                            }
                    }
                    labeledField("Reps high") { TextField("high", text: stringBinding(for: $exercise.repsHigh)).keyboardType(.numberPad) }
                }

                Toggle("Per side (e.g. \"8+8\")", isOn: perSideBinding($exercise.perSide))
                    .font(.tempoCaption1)
                    .tint(Color.tempoSignal)

                HStack(spacing: TempoSpacing.md) {
                    labeledField("Weight (\(weightUnit.abbreviation))") {
                        TextField("weight", text: weightBinding(kgValue: $exercise.weightKg, unit: weightUnit))
                            .keyboardType(.decimalPad)
                    }
                    labeledField("RPE") { TextField("rpe", text: stringBinding(for: $exercise.rpe)).keyboardType(.decimalPad) }
                    labeledField("% 1RM") { TextField("pct", text: percentBinding($exercise.percentOf1RM)).keyboardType(.numberPad) }
                }

                // §5 — show how the % will actually be read BEFORE saving, so
                // "70%" never silently becomes a guessed weight.
                percentReadingHint

                HStack(spacing: TempoSpacing.md) {
                    labeledField("Rest (sec)") {
                        TextField("rest", text: stringBinding(for: $exercise.restSeconds)).keyboardType(.numberPad)
                    }
                    labeledField("Superset #") { TextField("group", text: stringBinding(for: $exercise.group)).keyboardType(.numberPad) }
                }
            }

            TextField("Notes (optional)", text: stringBinding(for: $exercise.notes))
                .font(.tempoCaption1)
        }
        .padding(.vertical, TempoSpacing.xs)
        .task(id: exercise.name) {
            autoMatchIfNeeded()
        }
        .sheet(isPresented: $showResearchEditor) {
            if case let .done(found) = research.state(for: exercise.name) {
                ExerciseResearchEditor(name: exercise.name, research: found) { edited in
                    research.update(edited, for: exercise.name)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerSheet(
                library: libraryExercises,
                onSelect: { chosen in
                    exercise.exerciseID = chosen?.id
                }
            )
        }
    }

    /// The equipment the trainer wrote for this row, when it conflicts with
    /// `matchedExercise`'s own equipment — fix #10. Non-nil here means Save
    /// will clone an equipment variant (TrainerProgramSaver) instead of
    /// linking straight to the match; this previews that before saving.
    private var conflictingWrittenEquipment: Equipment? {
        guard let matchedExercise else {
            return nil
        }
        guard let written = ExerciseMatcher.writtenEquipment(in: exercise.name), written != matchedExercise.equipment else {
            return nil
        }
        return written
    }

    private var matchIndicator: some View {
        HStack(spacing: TempoSpacing.xs) {
            if let matchedExercise, let conflictingWrittenEquipment {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.tempoSuccess)
                Text(
                    "→ \(TrainerProgramSaver.variantName(rawName: exercise.name, matchedName: matchedExercise.name, equipment: conflictingWrittenEquipment)) (new variant of \(matchedExercise.name))"
                )
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
            } else if let matchedExercise {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.tempoSuccess)
                Text("Matches \(matchedExercise.name)")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else if !exercise.name.trimmingCharacters(in: .whitespaces).isEmpty {
                newExerciseStatus
            }
            Spacer()
            Button("Change") { showPicker = true }
                .font(.tempoCaption2)
        }
    }

    /// Not in the library: a NEW badge plus what research found — Save adds
    /// it to the library with these details (TrainerProgramSaver).
    @ViewBuilder
    private var newExerciseStatus: some View {
        Text("NEW")
            .font(.tempoCaption2.weight(.bold))
            .foregroundStyle(Color.tempoTextInverse)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.tempoSignal, in: Capsule())
            .accessibilityIdentifier("exerciseResearch.new")
        switch research.state(for: exercise.name) {
        case .loading:
            ProgressView()
                .controlSize(.mini)
            Text("Looking it up…")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
        case let .done(found):
            Button {
                showResearchEditor = true
            } label: {
                Text("\(found.summary) · Details")
                    .font(.tempoCaption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("exerciseResearch.details")
        case let .failed(message):
            Text(message)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoWarning)
                .lineLimit(1)
            Button("Retry") { Task { await research.lookUp(exercise.name) } }
                .font(.tempoCaption2)
                .buttonStyle(.borderless)
        case nil:
            if research.isAutomatic {
                Text("Will be added to your library")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                Button("Look it up with AI") { Task { await research.lookUp(exercise.name) } }
                    .font(.tempoCaption2)
                    .buttonStyle(.borderless)
            }
        }
    }

    /// §5 — "70% → effort, calibrate first set" vs "70% of your 100 kg max =
    /// 70 kg", read against the MATCHED library exercise (unmatched → always
    /// effort, since there's no exercise to hold history against).
    @ViewBuilder
    private var percentReadingHint: some View {
        if let pct = exercise.percentOf1RM, pct > 0, (exercise.weightKg ?? 0) <= 0 {
            let percentLabel = "\(Int((pct * 100).rounded()))%"
            if let matched = matchedExercise,
               !TrainingViewModel.isIsolationOrMachine(matched),
               let e1RM = TrainingViewModel.reliableEstimated1RM(for: matched), e1RM > 0
            {
                let maxDisplay = Int(WeightUnit.kg.convert(e1RM, to: weightUnit).rounded())
                let weightDisplay = Int(WeightUnit.kg.convert(e1RM * min(pct, 1.1), to: weightUnit).rounded())
                Text("\(percentLabel) of your \(maxDisplay) \(weightUnit.abbreviation) max = \(weightDisplay) \(weightUnit.abbreviation)")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            } else {
                Text("\(percentLabel) → effort, calibrate first set")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoAmber)
            }
        }
    }

    private func autoMatchIfNeeded() {
        guard exercise.exerciseID == nil else {
            return
        }
        guard let match = ExerciseMatcher.match(exercise.name, in: candidates) else {
            return
        }
        exercise.exerciseID = match.id
    }

    private func labeledField(_ label: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            field()
                .font(.tempoCaption1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ExercisePickerSheet

private struct ExercisePickerSheet: View {
    let library: [Exercise]
    var onSelect: (Exercise?) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var searchText = ""

    private var filtered: [Exercise] {
        guard !searchText.isEmpty else {
            return library
        }
        let query = ExerciseMatcher.normalize(searchText)
        return library.filter { ExerciseMatcher.normalize($0.name).contains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Button("Create a new custom exercise") {
                    onSelect(nil)
                    dismiss()
                }
                .listRowBackground(Color.tempoSurfaceCard)
                ForEach(filtered) { exercise in
                    Button {
                        onSelect(exercise)
                        dismiss()
                    } label: {
                        HStack {
                            Text(exercise.name).foregroundStyle(Color.tempoTextPrimary)
                            Spacer()
                            Text(exercise.muscleGroup.displayName)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                    .listRowBackground(Color.tempoSurfaceCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Match Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // See TrainerProgramImportView — matches the standalone-screen
        // convention for a modally-presented dark-only screen.
        .preferredColorScheme(.dark)
    }
}

// MARK: - Binding helpers

private func stringBinding(for value: Binding<String?>) -> Binding<String> {
    Binding<String>(
        get: { value.wrappedValue ?? "" },
        set: { newText in value.wrappedValue = newText.isEmpty ? nil : newText }
    )
}

private func stringBinding(for value: Binding<Int?>) -> Binding<String> {
    Binding<String>(
        get: { value.wrappedValue.map(String.init) ?? "" },
        set: { newText in
            let trimmed = newText.trimmingCharacters(in: .whitespaces)
            value.wrappedValue = trimmed.isEmpty ? nil : Int(trimmed)
        }
    )
}

private func stringBinding(for value: Binding<Double?>) -> Binding<String> {
    Binding<String>(
        get: { value.wrappedValue.map { String(format: "%.1f", $0) } ?? "" },
        set: { newText in
            let cleaned = newText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            value.wrappedValue = cleaned.isEmpty ? nil : Double(cleaned)
        }
    )
}

/// `perSide` is `Bool?` (nil = not per-side); the toggle only cares about
/// true/false and always writes an explicit value, never nil.
private func perSideBinding(_ value: Binding<Bool?>) -> Binding<Bool> {
    Binding<Bool>(
        get: { value.wrappedValue ?? false },
        set: { newValue in value.wrappedValue = newValue }
    )
}

/// Displays/edits a kg-stored weight in the user's preferred unit.
private func weightBinding(kgValue: Binding<Double?>, unit: WeightUnit) -> Binding<String> {
    Binding<String>(
        get: { kgValue.wrappedValue.map { String(format: "%.1f", WeightUnit.kg.convert($0, to: unit)) } ?? "" },
        set: { newText in
            let cleaned = newText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty, let value = Double(cleaned) else {
                kgValue.wrappedValue = nil
                return
            }
            kgValue.wrappedValue = unit.convert(value, to: .kg)
        }
    )
}

/// Displays/edits a 0-1 fraction as a whole percentage ("75" <-> 0.75).
private func percentBinding(_ fraction: Binding<Double?>) -> Binding<String> {
    Binding<String>(
        get: { fraction.wrappedValue.map { String(Int(($0 * 100).rounded())) } ?? "" },
        set: { newText in
            let trimmed = newText.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let percent = Int(trimmed) else {
                fraction.wrappedValue = nil
                return
            }
            fraction.wrappedValue = Double(percent) / 100
        }
    )
}
