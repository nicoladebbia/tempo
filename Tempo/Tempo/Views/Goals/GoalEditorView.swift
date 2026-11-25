//
// GoalEditorView.swift
// Tempo
//
// Set, change or remove the one goal: a body weight, a lift's estimated
// one-rep max, or a run time, with a date. Reached from Settings > Profile >
// Goal and from the "Set a goal" link on Today.
//

import SwiftData
import SwiftUI

// MARK: - GoalEditorView

struct GoalEditorView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    @Query
    private var allSettings: [UserSettings]

    /// The goal being edited, fetched once when the screen opens. A `@Query`
    /// for it here, next to the same query on the Profile screen that pushes
    /// this one, made both screens redraw forever.
    @State
    private var existing: Goal?
    /// Lifts the person has logged come first; the rest of the library follows.
    @State
    private var liftChoices: [String] = []
    /// The type the typed numbers belong to; a different type starts them empty.
    @State
    private var textKind: GoalKind = .bodyWeight
    @State
    private var draft = GoalDraft(targetDate: Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date())
    @State
    private var loaded = false
    @State
    private var saved = 0
    /// The "Goal removed" toast, with Undo.
    @State
    private var toast: ToastData?
    /// The reading the goal starts from, read when the screen opens and again
    /// when the type, lift or distance changes. Never fetched in `body`: a
    /// fetch there made the screen redraw itself forever.
    @State
    private var reading: Double?
    /// The first day a goal can end. Fixed when the screen opens so the date
    /// picker's range does not move on every redraw.
    @State
    private var earliestDate = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    )

    private var unit: WeightUnit {
        allSettings.first?.weightUnit ?? .kg
    }

    private var problem: GoalDraft.Problem? {
        draft.problem(now: Date(), unit: unit)
    }

    var body: some View {
        TideSettingsPage {
            SettingsFormCard(title: "What are you aiming for") {
                SettingsControlRow(label: "Type", icon: draft.kind.icon) {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(GoalKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Tide.text2)
                    .accessibilityIdentifier("goal.kind")
                }
                SettingsRowDivider()
                targetRows
                SettingsRowDivider()
                SettingsControlRow(label: "By", icon: "calendar") {
                    DatePicker(
                        "By", selection: $draft.targetDate,
                        in: earliestDate...,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("goal.date")
                }
            }

            SettingsFormCard(footnote: startFootnote) {
                SettingsInfoRow(label: "Now", value: currentText, icon: "scope")
                    .explains(Explainer.goalReading(draft.kind).showing(reading == nil ? nil : currentText))
            }

            Button(action: save) {
                Label(existing == nil ? "Set goal" : "Save goal", systemImage: "checkmark")
            }
            .buttonStyle(.tidePrimary)
            .disabled(problem != nil)
            .accessibilityIdentifier("goal.save")

            if let hint = problemHint {
                Text(hint)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .accessibilityIdentifier("goal.hint")
            }

            if existing != nil {
                // No "are you sure?": the toast that follows has Undo.
                Button("Remove goal", role: .destructive, action: remove)
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("goal.remove")
            }
        }
        .navigationTitle("Goal")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: saved)
        // At the bottom, so it never covers the navigation bar or the Remove button.
        .tempoToast($toast, placement: .bottom)
        .firstTip("goals.editor", "Pick a type, a target and a date. Tempo draws a line to it and tells you if you are ahead.", systemImage: "target")
        .onAppear {
            load()
            reading = readCurrent()
        }
        .onChange(of: draft.kind) { _, kind in
            if kind != textKind {
                draft.clearTarget()
                textKind = kind
            }
            if kind == .liftE1RM, draft.exercise == nil {
                draft.exercise = liftChoices.first
            }
            reading = readCurrent()
        }
        .onChange(of: draft.exercise) { _, _ in reading = readCurrent() }
        .onChange(of: draft.runDistanceKm) { _, _ in reading = readCurrent() }
    }

    // MARK: Rows

    @ViewBuilder
    private var targetRows: some View {
        switch draft.kind {
        case .bodyWeight:
            SettingsControlRow(label: "Target weight", icon: "scalemass.fill") {
                numberField("Target", text: $draft.weightText, suffix: unit.abbreviation, id: "goal.weight")
            }
        case .liftE1RM:
            SettingsControlRow(label: "Lift", icon: "dumbbell.fill") {
                Picker("Lift", selection: $draft.exercise) {
                    Text("Choose").tag(String?.none)
                    ForEach(liftChoices, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
                .pickerStyle(.menu)
                .tint(Tide.text2)
                .accessibilityIdentifier("goal.exercise")
            }
            SettingsRowDivider()
            SettingsControlRow(label: "Target one-rep max", icon: "target") {
                numberField("Target", text: $draft.weightText, suffix: unit.abbreviation, id: "goal.weight")
            }
        case .runTime:
            SettingsControlRow(label: "Distance", icon: "figure.run") {
                Picker("Distance", selection: $draft.runDistanceKm) {
                    ForEach(GoalDraft.runDistances, id: \.self) { km in
                        Text(GoalFormat.distance(km: km)).tag(km)
                    }
                }
                .pickerStyle(.menu)
                .tint(Tide.text2)
                .accessibilityIdentifier("goal.distance")
            }
            SettingsRowDivider()
            SettingsControlRow(label: "Target time", icon: "timer") {
                HStack(spacing: Tide.s1) {
                    numberField("min", text: $draft.minutesText, suffix: "min", id: "goal.minutes", wholeNumbers: true)
                    numberField("sec", text: $draft.secondsText, suffix: "sec", id: "goal.seconds", wholeNumbers: true)
                }
            }
        }
    }

    private func numberField(
        _ placeholder: String, text: Binding<String>, suffix: String, id: String, wholeNumbers: Bool = false
    ) -> some View {
        HStack(spacing: Tide.s1) {
            TextField(placeholder, text: text)
                .keyboardType(wholeNumbers ? .numberPad : .decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Tide.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(Tide.text)
                .frame(minWidth: Tide.hit, maxWidth: 88, minHeight: Tide.hit)
                .accessibilityIdentifier(id)
            Text(suffix)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
        }
    }

    // MARK: Words

    private func readCurrent() -> Double? {
        switch draft.kind {
        case .bodyWeight: GoalReader.latestWeightKg(in: modelContext)
        case .liftE1RM: GoalReader.bestE1RM(named: draft.exercise, in: modelContext)
        case .runTime: GoalReader.bestRunSeconds(distanceKm: draft.runDistanceKm, in: modelContext)
        }
    }

    private var currentText: String {
        reading.map { GoalFormat.value($0, kind: draft.kind, unit: unit) } ?? "No reading yet"
    }

    private var startFootnote: String {
        reading == nil
            ? "Your first reading after you set this becomes the starting point."
            : "This is where your line starts. Tempo tells you if you are ahead, on track or behind it."
    }

    private var problemHint: String? {
        if problem == nil, draft.alreadyReached(current: reading, unit: unit) {
            return "You are already there. Pick a harder target."
        }
        return switch problem {
        case .needsExercise: "Choose a lift."
        case .needsTarget: draft.kind == .runTime ? "Enter a time." : "Enter a target."
        case .needsDate: "Pick a date after today."
        case nil: String?.none
        }
    }

    // MARK: Actions

    private func load() {
        guard !loaded else {
            return
        }
        loaded = true
        var latest = FetchDescriptor<Goal>(
            predicate: #Predicate<Goal> { $0.isActive == true },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        latest.fetchLimit = 1
        existing = (try? modelContext.fetch(latest))?.first
        if let existing {
            draft = GoalDraft(goal: existing, unit: unit)
        }
        textKind = draft.kind
        let library = (try? modelContext.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let logged = library.filter { !($0.history ?? []).isEmpty }.map(\.name)
        liftChoices = logged.isEmpty ? library.filter(\.isCompound).map(\.name) : logged
    }

    private func save() {
        guard problem == nil else {
            return
        }
        let now = Date()
        let start = readCurrent()
        if let existing {
            draft.apply(to: existing, unit: unit, start: start, now: now)
        } else {
            let goal = Goal(kind: draft.kind, targetValue: draft.targetValue(unit: unit) ?? 0, targetDate: draft.targetDate)
            draft.apply(to: goal, unit: unit, start: start, now: now)
            modelContext.insert(goal)
        }
        try? modelContext.save()
        saved += 1
        toast = nil
        NotificationCenter.default.post(name: .tempoGoalChanged, object: nil)
        dismiss()
    }

    /// Takes the goal off at once and offers Undo. The screen stays, back to an
    /// empty "set a goal" form, so the toast has somewhere to be seen.
    private func remove() {
        guard let goal = existing else {
            return
        }
        let state = GoalUndo.remove(goal, in: modelContext)
        existing = nil
        draft = GoalDraft(targetDate: Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date())
        textKind = draft.kind
        reading = readCurrent()
        toast = ToastData(message: "Goal removed.", style: .info, actionTitle: "Undo") {
            if GoalUndo.restore(state, in: modelContext) {
                // Read the goal back into the form, exactly as it was.
                loaded = false
                load()
                reading = readCurrent()
            } else {
                // Another goal was set in the meantime: say so rather than do nothing.
                toast = ToastData(message: "Can't bring that goal back: you set another.", style: .info)
            }
        }
    }
}

extension Notification.Name {
    /// A goal was set, changed or removed.
    static let tempoGoalChanged = Notification.Name("tempoGoalChanged")
}
