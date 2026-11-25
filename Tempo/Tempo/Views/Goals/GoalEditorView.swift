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

    @Query(filter: #Predicate<Goal> { $0.isActive == true }, sort: \Goal.createdAt, order: .reverse)
    private var goals: [Goal]
    @Query
    private var allSettings: [UserSettings]
    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @State
    private var draft = GoalDraft(targetDate: Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date())
    @State
    private var loaded = false
    @State
    private var showRemove = false
    @State
    private var saved = 0

    private var unit: WeightUnit {
        allSettings.first?.weightUnit ?? .kg
    }

    private var existing: Goal? {
        goals.first
    }

    /// Lifts the person has logged come first; the rest of the library follows.
    private var liftChoices: [String] {
        let logged = exercises.filter { !($0.history ?? []).isEmpty }.map(\.name)
        return logged.isEmpty ? exercises.filter(\.isCompound).map(\.name) : logged
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
                        in: (Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())...,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("goal.date")
                }
            }

            SettingsFormCard(footnote: startFootnote) {
                SettingsInfoRow(label: "Now", value: currentText, icon: "scope")
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
                Button("Remove goal", role: .destructive) { showRemove = true }
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("goal.remove")
            }
        }
        .navigationTitle("Goal")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: saved)
        .confirmationDialog("Remove this goal?", isPresented: $showRemove, titleVisibility: .visible) {
            Button("Remove goal", role: .destructive, action: remove)
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your readings stay. Only the target goes.")
        }
        .onAppear(perform: load)
        .onChange(of: draft.kind) { _, kind in
            if kind == .liftE1RM, draft.exercise == nil {
                draft.exercise = liftChoices.first
            }
        }
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

    private var currentReading: Double? {
        switch draft.kind {
        case .bodyWeight: GoalReader.latestWeightKg(in: modelContext)
        case .liftE1RM: GoalReader.bestE1RM(named: draft.exercise, in: modelContext)
        case .runTime: GoalReader.bestRunSeconds(distanceKm: draft.runDistanceKm, in: modelContext)
        }
    }

    private var currentText: String {
        currentReading.map { GoalFormat.value($0, kind: draft.kind, unit: unit) } ?? "No reading yet"
    }

    private var startFootnote: String {
        currentReading == nil
            ? "Your first reading after you set this becomes the starting point."
            : "This is where your line starts. Tempo tells you if you are ahead, on track or behind it."
    }

    private var problemHint: String? {
        switch problem {
        case .needsExercise: "Choose a lift."
        case .needsTarget: draft.kind == .runTime ? "Enter a time." : "Enter a target."
        case .needsDate: "Pick a date after today."
        case nil: nil
        }
    }

    // MARK: Actions

    private func load() {
        guard !loaded else {
            return
        }
        loaded = true
        if let existing {
            draft = GoalDraft(goal: existing, unit: unit)
        }
    }

    private func save() {
        guard problem == nil else {
            return
        }
        let now = Date()
        let start = currentReading
        if let existing {
            draft.apply(to: existing, unit: unit, start: start, now: now)
        } else {
            let goal = Goal(kind: draft.kind, targetValue: draft.targetValue(unit: unit) ?? 0, targetDate: draft.targetDate)
            draft.apply(to: goal, unit: unit, start: start, now: now)
            modelContext.insert(goal)
        }
        try? modelContext.save()
        saved += 1
        NotificationCenter.default.post(name: .tempoGoalChanged, object: nil)
        dismiss()
    }

    private func remove() {
        if let existing {
            existing.isActive = false
            try? modelContext.save()
            NotificationCenter.default.post(name: .tempoGoalChanged, object: nil)
        }
        dismiss()
    }
}

extension Notification.Name {
    /// A goal was set, changed or removed.
    static let tempoGoalChanged = Notification.Name("tempoGoalChanged")
}
