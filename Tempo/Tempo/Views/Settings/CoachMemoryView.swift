//
// CoachMemoryView.swift
// Tempo
//
// Lets Nicola inspect what the Coach has learned about him. Lists active
// preferences grouped by subject, supports swipe-delete (sets isActive
// false rather than hard-deleting so we keep history), an edit sheet,
// and a manual-add form for user-stated facts.
//
// Per `.plans/coach-agent-plan.md` Phase 8.
//

import SwiftData
import SwiftUI

struct CoachMemoryView: View {

    @Environment(\.modelContext)
    private var modelContext

    @Query(
        filter: #Predicate<LearnedPreference> { $0.isActive },
        sort: \LearnedPreference.lastSeenAt,
        order: .reverse
    )
    private var preferences: [LearnedPreference]

    @State private var editing: LearnedPreference?
    @State private var showingAdd = false

    var body: some View {
        List {
            if preferences.isEmpty {
                emptyState
                    .listRowBackground(Color.tempoSurfaceCard)
            } else {
                ForEach(groupedPreferences, id: \.subject) { group in
                    Section(header: Text(prettySubject(group.subject))) {
                        ForEach(group.items) { pref in
                            preferenceRow(pref)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(pref)
                                    } label: {
                                        Label("Forget", systemImage: "trash")
                                    }
                                }
                                .onTapGesture { editing = pref }
                        }
                    }
                    .listRowBackground(Color.tempoSurfaceCard)
                }
            }
        }
        .navigationTitle("Coach's Memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { pref in
            EditPreferenceSheet(preference: pref)
        }
        .sheet(isPresented: $showingAdd) {
            AddPreferenceSheet()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("Coach hasn't learned anything yet.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Preferences get added as you chat with the coach, or you can add one manually with +.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(.vertical, TempoSpacing.sm)
    }

    // MARK: - Row

    private func preferenceRow(_ pref: LearnedPreference) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack(alignment: .top) {
                Text(pref.text)
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                if pref.userVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.tempoSuccess)
                        .accessibilityLabel("User confirmed")
                }
            }
            HStack(spacing: TempoSpacing.sm) {
                Text(sourceLabel(pref.source))
                Text("·")
                Text("conf \(String(format: "%.2f", pref.confidence))")
                Text("·")
                Text("evidence ×\(pref.evidenceCount)")
            }
            .font(.tempoCaption2)
            .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(.vertical, 2)
    }

    private func sourceLabel(_ s: LearnedPreference.Source) -> String {
        switch s {
        case .explicit: "user-stated"
        case .observed: "observed"
        case .inferred: "inferred"
        case .userVerified: "confirmed"
        }
    }

    private func prettySubject(_ subject: String) -> String {
        subject
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " · ")
            .capitalized
    }

    // MARK: - Grouping

    private var groupedPreferences: [SubjectGroup] {
        Dictionary(grouping: preferences, by: \.subject)
            .map { SubjectGroup(subject: $0.key, items: $0.value) }
            .sorted { $0.subject < $1.subject }
    }

    private struct SubjectGroup {
        let subject: String
        let items: [LearnedPreference]
    }

    // MARK: - Actions

    private func delete(_ pref: LearnedPreference) {
        pref.deactivate()
        try? modelContext.save()
    }
}

// MARK: - Edit sheet

struct EditPreferenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var preference: LearnedPreference

    var body: some View {
        NavigationStack {
            Form {
                Section("Statement") {
                    TextField("Preference", text: $preference.text, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("Confidence") {
                    Slider(value: $preference.confidence, in: 0...1, step: 0.05)
                    Text("\(String(format: "%.2f", preference.confidence))")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Section {
                    Toggle("User confirmed (pin)", isOn: Binding(
                        get: { preference.userVerified },
                        set: { newValue in
                            if newValue { preference.markUserVerified() }
                            else { preference.userVerified = false }
                        }
                    ))
                }
            }
            .navigationTitle("Edit Preference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Add sheet

struct AddPreferenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var text: String = ""
    @State private var subject: String = LearnedPreferenceSubject.generalCommunicationStyle
    @State private var confidence: Double = 0.9

    private let subjects: [(label: String, value: String)] = [
        ("Meal · breakfast", LearnedPreferenceSubject.mealTimingBreakfast),
        ("Meal · lunch", LearnedPreferenceSubject.mealTimingLunch),
        ("Meal · dinner", LearnedPreferenceSubject.mealTimingDinner),
        ("Meal · snack", LearnedPreferenceSubject.mealTimingSnack),
        ("Disliked ingredients", LearnedPreferenceSubject.mealContentDisliked),
        ("Cuisine", LearnedPreferenceSubject.mealContentCuisine),
        ("Training intensity", LearnedPreferenceSubject.trainingIntensity),
        ("Sleep · bedtime", LearnedPreferenceSubject.sleepBedtime),
        ("Sleep · wake", LearnedPreferenceSubject.sleepWake),
        ("Study peak hours", LearnedPreferenceSubject.studyPeakHours),
        ("Coaching tone", LearnedPreferenceSubject.generalCoachingTone),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Statement") {
                    TextField("e.g. Lights out by 23:00", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("Subject") {
                    Picker("Subject", selection: $subject) {
                        ForEach(subjects, id: \.value) { item in
                            Text(item.label).tag(item.value)
                        }
                    }
                }
                Section("Confidence") {
                    Slider(value: $confidence, in: 0...1, step: 0.05)
                    Text("\(String(format: "%.2f", confidence))")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .navigationTitle("Add Preference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let pref = LearnedPreference(
                            text: trimmed,
                            subject: subject,
                            confidence: confidence,
                            source: .userVerified,
                            userVerified: true
                        )
                        modelContext.insert(pref)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
