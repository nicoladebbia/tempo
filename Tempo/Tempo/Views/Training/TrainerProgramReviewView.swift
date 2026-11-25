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
    /// Weekly-upload feature — chosen here (and editable later on
    /// TrainerProgramView). Pre-selected in `init(parsed:...)`.
    @State
    private var cadence: TrainerProgramCadence = .block
    @State
    private var weeks: [ProgramWeek]
    @State
    private var autoAssignedWeekdays: Bool
    /// Import warnings from the parser (e.g. a long source that was cut off).
    private var importWarnings: [String] = []
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
        onSaved: @escaping () -> Void
    ) {
        editingProgram = nil
        _name = State(initialValue: parsed.name)
        _startDate = State(initialValue: TrainingCalendar.mondayOfWeek(containing: Date()))
        _weeks = State(initialValue: parsed.weeks)
        _autoAssignedWeekdays = State(initialValue: parsed.autoAssignedWeekdays)
        importWarnings = parsed.warnings
        // Weekly-upload feature — pre-select weekly for a single-week import
        // (the common "trainer sends one week at a time" shape), block
        // otherwise. Always editable below before saving.
        _cadence = State(initialValue: parsed.weeks.count == 1 ? .weekly : .block)
        self.sourceKind = sourceKind
        self.sourceText = sourceText
        self.onSaved = onSaved
    }

    /// Fix #11(a) — edit flow for an already-saved program.
    init(editingProgram program: TrainerProgram, onSaved: @escaping () -> Void) {
        editingProgram = program
        _name = State(initialValue: program.name)
        _startDate = State(initialValue: program.startDate)
        _repeats = State(initialValue: program.repeats)
        _autoWarmups = State(initialValue: program.warmupsEnabled)
        _scheduleMode = State(initialValue: program.scheduleMode)
        _cadence = State(initialValue: program.cadence)
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

    /// Weekly-upload feature (fix #5) — a brand-new WEEKLY program replacing
    /// an existing active one is never manually timed: the upload's own
    /// weekday decides it (`TrainerProgramWeeklyUpload.uploadTiming`). nil
    /// when there's nothing to replace, or this import isn't weekly (the
    /// existing "starts now / after current / on a date" picker applies
    /// instead — see `startTiming`).
    private var weeklyAutoTiming: TrainerProgramWeeklyUpload.UploadTiming? {
        guard cadence == .weekly, otherActiveProgram != nil else {
            return nil
        }
        return TrainerProgramWeeklyUpload.uploadTiming(forUploadOn: Date())
    }

    var body: some View {
        reviewContent
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
            TrainPlanPage {
                programSection
                if !importWarnings.isEmpty {
                    TrainPlanCard {
                        ForEach(importWarnings, id: \.self) { warning in
                            Text(warning)
                                .font(Tide.caption)
                                .foregroundStyle(TideTrain.caution)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if autoAssignedWeekdays {
                    TrainPlanCard {
                        Text("We placed these around your football — change any day.")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                TrainPlanAddButton(title: String(localized: "Add Week"), systemImage: "plus.circle") {
                    addWeek()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .trainSheetRoot()
            .navigationTitle(editingProgram == nil ? String(localized: "Review Program") : String(localized: "Edit Program"))
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
    }

    // MARK: - Program-level section

    private var programSection: some View {
        TrainPlanCard(label: String(localized: "Program")) {
            TextField("Program name", text: $name)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .tideFieldSurface()

            // Weekly-upload feature — decides the duration text, the "New
            // week — upload" prompt/reminders, and (below) how a new upload
            // replaces the old one.
            TrainPlanPickerRow(
                title: String(localized: "How does your trainer send programs?"),
                detail: cadence == .weekly
                    ? String(localized: "Tempo reminds you every Sunday to upload the next one.")
                    : String(localized: "Runs for its full length, then repeats or ends."),
                stacked: true,
                selection: $cadence
            ) {
                ForEach(TrainerProgramCadence.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }

            if weeklyAutoTiming == nil {
                TrainPlanDivider()
                let startLabel = Text("Start date (Monday)")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                let startPicker = DatePicker(
                    "Start date (Monday)",
                    selection: Binding(
                        get: { startDate },
                        set: { startDate = TrainingCalendar.mondayOfWeek(containing: $0) }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .tint(Color.accentColor)
                // The label sits beside the date, or above it when it won't fit.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Tide.s2) {
                        startLabel
                        Spacer(minLength: Tide.s2)
                        startPicker
                    }
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        startLabel
                        startPicker
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
                .disabled(startTiming == .afterCurrent)
            }

            if weeks.count > 1 {
                TrainPlanDivider()
                TrainPlanToggleRow(title: String(localized: "Repeats after last week"), isOn: $repeats)
            }

            TrainPlanDivider()
            TrainPlanToggleRow(
                title: String(localized: "Tempo warm-up sets"),
                detail: String(localized: "Add a 50%/75% ramp before each lift. Off — exactly what your trainer wrote."),
                isOn: $autoWarmups
            )

            // Fix #6 — schedule mode, editable here and later on
            // TrainerProgramView.
            TrainPlanDivider()
            TrainPlanPickerRow(
                title: String(localized: "Schedule"),
                detail: scheduleMode.explanation,
                selection: $scheduleMode
            ) {
                ForEach(TrainerProgramScheduleMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            // Weekly-upload feature (fix #5) — no manual picker: the upload's
            // own weekday decides start/replace timing.
            if let otherActiveProgram, let weeklyAutoTiming {
                TrainPlanDivider()
                Text(weeklyReplaceExplanation(otherActiveProgram, timing: weeklyAutoTiming))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let otherActiveProgram {
                // Fix #11(b) — queue behind the current program instead of
                // replacing it immediately (block cadence only).
                TrainPlanDivider()
                TrainPlanPickerRow(
                    title: String(localized: "Starts"),
                    detail: startTiming == .now ? nil : queueExplanation,
                    stacked: true,
                    selection: $startTiming
                ) {
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
            }
        }
    }

    /// "Starts Monday 28 Sep and replaces "Coach — Block 4" once this week
    /// ends." / "Starts Monday 22 Sep and replaces "Coach — Block 4" now."
    private func weeklyReplaceExplanation(_ other: TrainerProgram, timing: TrainerProgramWeeklyUpload.UploadTiming) -> String {
        let dateText = timing.startDate.formatted(date: .abbreviated, time: .omitted)
        return timing.isQueued
            ? String(localized: "Starts \(dateText) and replaces \"\(other.name)\" once this week ends — your current one keeps running until then.")
            : String(localized: "Starts \(dateText) and replaces \"\(other.name)\" now.")
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
            String(localized: "Starts \(startDate.formatted(date: .abbreviated, time: .omitted)) — auto-activates that day; your current program keeps running until then.")
        case .onDate:
            String(localized: "Starts \(startDate.formatted(date: .abbreviated, time: .omitted)) — pick the date above. Your current program keeps running until then.")
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
                    cadence: cadence,
                    modelContext: modelContext,
                    trainingEngine: services.trainingEngine,
                    whoop: services.whoop,
                    healthKit: services.healthKit,
                    onNewExercisesCreated: kickOffImageGeneration
                )
            } else {
                // Weekly-upload feature (fix #5) — the upload's own weekday
                // decides start/replace timing; only a `.block` import (or a
                // weekly one with nothing else active) uses the manual
                // "starts now / after current / on a date" picker.
                let effectiveStartDate = weeklyAutoTiming?.startDate ?? startDate
                let queuedActivationDate = weeklyAutoTiming?.queuedActivationDate
                    ?? (startTiming == .now ? nil : startDate)
                let saved = try TrainerProgramSaver.save(
                    name: name,
                    startDate: effectiveStartDate,
                    weeks: weeks,
                    repeats: weeks.count > 1 ? repeats : true,
                    sourceKind: sourceKind,
                    sourceText: sourceText,
                    modelContext: modelContext,
                    autoWarmups: autoWarmups,
                    scheduleMode: scheduleMode,
                    cadence: cadence,
                    queuedActivationDate: queuedActivationDate,
                    onNewExercisesCreated: kickOffImageGeneration
                )
                _ = saved
            }
            onSaved()
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// feat/exercise-images — fire-and-forget: never blocks the save, never
    /// surfaces an error (ExerciseImageService.imageData never throws; it
    /// just silently gives up per exercise on any failure). Each call also
    /// warms ExerciseImageService's disk cache, so the newly-created
    /// exercise's thumbnail is likely ready by the time the user reaches
    /// Today's list or the library.
    private func kickOffImageGeneration(for newExercises: [Exercise]) {
        Task {
            for exercise in newExercises {
                _ = await services.exerciseImages.imageData(for: exercise)
            }
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
        TrainPlanCard {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text("Week \(weekNumber)").tideLabel()
                Spacer(minLength: Tide.s2)
                if canRemoveWeek {
                    Button("Remove", role: .destructive, action: onRemoveWeek)
                        .font(Tide.caption)
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                }
            }

            // Shown Monday → Sunday. Display order only: the stored order
            // backs each session's key, so the array itself isn't re-sorted.
            ForEach(daysInWeekdayOrder, id: \.id) { day in
                DayEditorView(
                    day: binding(forDay: day.id, fallback: day),
                    pairedSessionLabel: pairedSessionLabel(for: day),
                    libraryExercises: libraryExercises,
                    weightUnit: weightUnit,
                    onRemoveDay: { removeDay(day.id) }
                )
                TrainPlanDivider()
            }

            TrainPlanAddButton(title: String(localized: "Add Day")) {
                addDay()
            }
        }
    }

    private var daysInWeekdayOrder: [ProgramDay] {
        week.days.enumerated()
            .sorted { ($0.element.weekday, $0.offset) < ($1.element.weekday, $1.offset) }
            .map(\.element)
    }

    /// Looks the day up by id on every read/write, so removing or re-dating a
    /// day never leaves a stale index behind.
    private func binding(forDay id: UUID, fallback: ProgramDay) -> Binding<ProgramDay> {
        Binding(
            get: { week.days.first { $0.id == id } ?? fallback },
            set: { newValue in
                if let index = week.days.firstIndex(where: { $0.id == id }) {
                    week.days[index] = newValue
                }
            }
        )
    }

    /// Two sessions land on the same weekday when a trainer schedules a
    /// lift + a conditioning session on the same day — call that out rather
    /// than let it read as an accidental duplicate.
    private func pairedSessionLabel(for day: ProgramDay) -> String? {
        let sameWeekday = week.days.filter { $0.weekday == day.weekday }
        guard sameWeekday.count == 2 else {
            return nil
        }
        return String(localized: "Lift + conditioning")
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
            VStack(alignment: .leading, spacing: Tide.s3) {
                TrainPlanPickerRow(title: String(localized: "Day"), selection: $day.weekday) {
                    ForEach(1 ... 7, id: \.self) { weekday in
                        Text(TrainerProgramView.shortWeekdayName(weekday)).tag(weekday)
                    }
                }
                // The user chose this day — it's no longer an auto-placement.
                .onChange(of: day.weekday) { _, _ in
                    day.weekdayGuessed = false
                }

                TrainPlanCellField(label: String(localized: "Title")) {
                    TextField("Day title (optional)", text: stringBinding(for: $day.title))
                }

                TrainPlanPickerRow(title: String(localized: "Focus"), selection: $day.focus) {
                    Text("None").tag(String?.none)
                    ForEach(Self.focusTypes, id: \.self) { type in
                        Text(type.displayName).tag(String?.some(type.rawValue))
                    }
                }

                TrainPlanCellField(label: String(localized: "Notes")) {
                    TextField("Day notes (optional)", text: stringBinding(for: $day.notes), axis: .vertical)
                }

                ForEach($day.exercises) { $exercise in
                    TrainPlanDivider()
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

                TrainPlanAddButton(title: String(localized: "Add Exercise")) {
                    addExercise()
                }

                Button("Remove This Day", role: .destructive, action: onRemoveDay)
                    .font(Tide.caption)
                    .frame(maxWidth: .infinity, minHeight: Tide.hit)
                    .contentShape(.rect)
            }
            .padding(.top, Tide.s2)
        } label: {
            VStack(alignment: .leading, spacing: Tide.hair) {
                HStack(spacing: Tide.s1) {
                    Text("\(TrainerProgramView.shortWeekdayName(day.weekday)) — \(day.title ?? (day.workoutType.displayName))")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if day.weekdayGuessed == true {
                        Image(systemName: "wand.and.stars")
                            .font(Tide.caption)
                            .foregroundStyle(TideTrain.caution)
                            .accessibilityLabel("Day auto-placed")
                    }
                }
                if let pairedSessionLabel {
                    Text(pairedSessionLabel)
                        .font(Tide.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text(String(localized: "\(day.exercises.count) exercises"))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
            .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
        }
        .tint(Tide.text3)
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
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(spacing: Tide.s2) {
                // Only shown once a library match is resolved — an
                // unmatched row has no equipment/muscle-group metadata yet
                // (ProgramExercise carries name + prescription only; that
                // metadata exists once TrainerProgramSaver creates the real
                // Exercise on import), so there's nothing to key an image by.
                if let matchedExercise {
                    ExerciseImageView(exercise: matchedExercise, style: .thumbnail)
                        .frame(width: TideTrain.rowThumb, height: TideTrain.rowThumb)
                }
                TextField("Exercise name", text: $exercise.name)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .trainPlanCell()
            }

            matchIndicator

            if isConditioning {
                TrainPlanCellField(label: String(localized: "Prescription")) {
                    TextField("e.g. 35' — 2' slow / 1' fast / 30\" walk", text: stringBinding(for: $exercise.detail), axis: .vertical)
                        .lineLimit(2 ... 4)
                }
                TrainPlanFieldRow {
                    TrainPlanCellField(label: String(localized: "RPE")) { TextField("rpe", text: stringBinding(for: $exercise.rpe)).keyboardType(.decimalPad) }
                    TrainPlanCellField(label: String(localized: "Rest (sec)")) {
                        TextField("rest", text: stringBinding(for: $exercise.restSeconds)).keyboardType(.numberPad)
                    }
                    TrainPlanCellField(label: String(localized: "Superset #")) {
                        TextField("group", text: stringBinding(for: $exercise.group)).keyboardType(.numberPad)
                    }
                }
            } else {
                TrainPlanFieldRow {
                    TrainPlanCellField(label: String(localized: "Sets")) {
                        TextField("sets", text: $setsText)
                            .keyboardType(.numberPad)
                            .onChange(of: setsText) { _, newValue in
                                if let parsed = Int(newValue), parsed > 0 {
                                    exercise.sets = parsed
                                }
                            }
                    }
                    TrainPlanCellField(label: String(localized: "Reps low")) {
                        TextField("low", text: $repsLowText)
                            .keyboardType(.numberPad)
                            .onChange(of: repsLowText) { _, newValue in
                                if let parsed = Int(newValue), parsed > 0 {
                                    exercise.repsLow = parsed
                                }
                            }
                    }
                    TrainPlanCellField(label: String(localized: "Reps high")) {
                        TextField("high", text: stringBinding(for: $exercise.repsHigh)).keyboardType(.numberPad)
                    }
                }

                TrainPlanToggleRow(title: String(localized: "Per side (e.g. \"8+8\")"), isOn: perSideBinding($exercise.perSide))

                TrainPlanFieldRow {
                    TrainPlanCellField(label: String(localized: "Weight (\(weightUnit.abbreviation))")) {
                        TextField("weight", text: weightBinding(kgValue: $exercise.weightKg, unit: weightUnit))
                            .keyboardType(.decimalPad)
                    }
                    TrainPlanCellField(label: String(localized: "RPE")) { TextField("rpe", text: stringBinding(for: $exercise.rpe)).keyboardType(.decimalPad) }
                    TrainPlanCellField(label: String(localized: "% 1RM")) {
                        TextField("pct", text: percentBinding($exercise.percentOf1RM)).keyboardType(.numberPad)
                    }
                }

                // §5 — show how the % will actually be read BEFORE saving, so
                // "70%" never silently becomes a guessed weight.
                percentReadingHint

                TrainPlanFieldRow {
                    TrainPlanCellField(label: String(localized: "Rest (sec)")) {
                        TextField("rest", text: stringBinding(for: $exercise.restSeconds)).keyboardType(.numberPad)
                    }
                    TrainPlanCellField(label: String(localized: "Superset #")) {
                        TextField("group", text: stringBinding(for: $exercise.group)).keyboardType(.numberPad)
                    }
                }
            }

            TextField("Notes (optional)", text: stringBinding(for: $exercise.notes))
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .trainPlanCell()

            HStack(spacing: Tide.s2) {
                Spacer(minLength: 0)
                TrainIconButton(systemImage: "chevron.up", label: String(localized: "Move up"), action: onMoveUp)
                    .disabled(!canMoveUp)
                TrainIconButton(systemImage: "chevron.down", label: String(localized: "Move down"), action: onMoveDown)
                    .disabled(!canMoveDown)
                TrainIconButton(systemImage: "trash", label: String(localized: "Remove exercise"), tint: Tide.danger, action: onRemove)
            }
        }
        .padding(.vertical, Tide.s1)
        .task(id: exercise.name) {
            autoMatchIfNeeded()
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
        let icon: String
        let tint: Color
        let message: String
        if let matchedExercise, let conflictingWrittenEquipment {
            icon = "checkmark.circle.fill"
            tint = TideTrain.positive
            message =
                String(localized: "→ \(TrainerProgramSaver.variantName(rawName: exercise.name, matchedName: matchedExercise.name, equipment: conflictingWrittenEquipment)) (new variant of \(matchedExercise.name))")
        } else if let matchedExercise {
            icon = "checkmark.circle.fill"
            tint = TideTrain.positive
            message = String(localized: "Matches \(matchedExercise.name)")
        } else {
            icon = "exclamationmark.circle.fill"
            tint = TideTrain.caution
            message = String(localized: "New exercise — will be added to your library")
        }

        return HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
            Image(systemName: icon)
                .font(Tide.caption)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tide.s2)
            Button("Change") { showPicker = true }
                .font(Tide.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .frame(minHeight: Tide.hit)
                .contentShape(.rect)
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
                let maxDisplay = WeightFormat.number(kg: e1RM, unit: weightUnit)
                let weightDisplay = WeightFormat.number(kg: e1RM * min(pct, 1.1), unit: weightUnit)
                Text("\(percentLabel) of your \(maxDisplay) \(weightUnit.abbreviation) max = \(weightDisplay) \(weightUnit.abbreviation)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            } else {
                Text("\(percentLabel) → effort, calibrate first set")
                    .font(Tide.caption)
                    .foregroundStyle(TideTrain.caution)
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
                .font(Tide.bodyStrong)
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: Tide.hit)
                .listRowBackground(Tide.fill)
                ForEach(filtered) { exercise in
                    Button {
                        onSelect(exercise)
                        dismiss()
                    } label: {
                        HStack(spacing: Tide.s2) {
                            Text(exercise.name)
                                .font(Tide.body)
                                .foregroundStyle(Tide.text)
                            Spacer(minLength: Tide.s2)
                            Text(exercise.muscleGroup.displayName)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
                        }
                        .frame(minHeight: Tide.hit)
                    }
                    .listRowBackground(Tide.fill)
                }
            }
            .scrollContentBackground(.hidden)
            .trainSheetRoot()
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
