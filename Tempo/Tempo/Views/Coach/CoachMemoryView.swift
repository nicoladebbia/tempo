//
// CoachMemoryView.swift
// Tempo
//
// Coach v2.1 Phase 8b — the trust + transparency surface.
//
// Three tabs by polarity (Likes / Dislikes / Hard Avoids). Within each
// tab, preferences are grouped by scope (Always / Weekdays / Hard
// Training Days / etc). Row: text + confidence bar + last-seen +
// source pill. Tap a row → edit sheet with text / scope / polarity
// + "Save" (becomes userVerified) and "This is wrong — delete".
// Footer: "Re-do Coach interview" link.
//
// Per .plans/coach-v2.1/05-ui-surfaces.md §3.
//

import SwiftData
import SwiftUI

// MARK: - CoachMemoryView

struct CoachMemoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<LearnedPreference> { $0.isActive })
    private var preferences: [LearnedPreference]

    @State private var selectedPolarity: LearnedPreference.Polarity = .positive
    @State private var editingPreference: LearnedPreference?
    @State private var presentingRedoInterview: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                polarityTabs
                groupedList
                footer
            }
            .background(Color.tempoBgPrimary.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.tempoGhost)
                }
            }
        }
        .sheet(item: $editingPreference) { pref in
            EditPreferenceSheet(preference: pref, onDelete: { delete(pref) })
        }
        .sheet(isPresented: $presentingRedoInterview) {
            CoachInterviewView { _ in
                presentingRedoInterview = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("Coach's Memory")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Coach knows \(activeCount) things about you.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
    }

    // MARK: - Polarity tabs

    private var polarityTabs: some View {
        HStack(spacing: TempoSpacing.sm) {
            polarityTab(.positive, label: "Likes")
            polarityTab(.negative, label: "Dislikes")
            polarityTab(.avoidAtAllCosts, label: "Hard Avoids")
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.bottom, TempoSpacing.sm)
    }

    private func polarityTab(_ polarity: LearnedPreference.Polarity, label: String) -> some View {
        let count = preferences.filter { $0.polarity == polarity }.count
        let isSelected = selectedPolarity == polarity
        return Button {
            selectedPolarity = polarity
        } label: {
            HStack(spacing: TempoSpacing.xs) {
                Text(label)
                    .font(.tempoCaption1)
                Text("(\(count))")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .padding(.horizontal, TempoSpacing.sm)
            .padding(.vertical, TempoSpacing.xs)
            .background(
                Capsule()
                    .fill(isSelected ? polarityColor(polarity).opacity(0.18) : Color.tempoSurfaceCard)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? polarityColor(polarity) : Color.clear,
                        lineWidth: 1
                    )
            )
            .foregroundStyle(Color.tempoTextPrimary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grouped list

    private var groupedList: some View {
        let groups = CoachMemoryGrouping.group(
            preferences: preferences,
            polarity: selectedPolarity
        )
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: TempoSpacing.md) {
                if groups.isEmpty {
                    emptyState
                } else {
                    ForEach(groups, id: \.scope) { group in
                        scopeSection(group)
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.md)
        }
    }

    private func scopeSection(_ group: CoachMemoryGrouping.Group) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("\(group.scope.displayLabel) (\(group.preferences.count))")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .tracking(TempoTracking.drillLabel)
            ForEach(group.preferences, id: \.id) { pref in
                preferenceRow(pref)
            }
        }
    }

    private func preferenceRow(_ pref: LearnedPreference) -> some View {
        Button { editingPreference = pref } label: {
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                HStack {
                    Text(pref.text)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if pref.needsReview {
                        Text("Review")
                            .font(.tempoCaption2)
                            .padding(.horizontal, TempoSpacing.xs)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.tempoAmber.opacity(0.18)))
                            .foregroundStyle(Color.tempoAmber)
                    }
                }
                HStack(spacing: TempoSpacing.sm) {
                    confidenceBar(pref.confidence)
                    Text(Int(pref.confidence * 100).description + "%")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    sourcePill(pref.source)
                    Spacer()
                    Text("last seen \(relativeDate(pref.lastSeenAt))")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                    .fill(Color.tempoSurfaceCard)
            )
        }
        .buttonStyle(.plain)
    }

    private func confidenceBar(_ confidence: Double) -> some View {
        // 10-segment bar — fill `floor(confidence * 10)` cells.
        let filled = Int((confidence * 10).rounded())
        return HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? Color.tempoSignal : Color.tempoSteel.opacity(0.25))
                    .frame(width: 6, height: 4)
            }
        }
    }

    private func sourcePill(_ source: LearnedPreference.Source) -> some View {
        let (label, color): (String, Color) = {
            switch source {
            case .explicit: return ("Explicit", Color.tempoInfo)
            case .observed: return ("Observed", Color.tempoTextTertiary)
            case .inferred: return ("Inferred", Color.tempoTextTertiary)
            case .userVerified: return ("Verified", Color.tempoSuccess)
            }
        }()
        return Text(label)
            .font(.tempoCaption2)
            .padding(.horizontal, TempoSpacing.xs)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.sm) {
            Spacer(minLength: TempoSpacing.xxl)
            Text(emptyStateMessage)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.lg)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateMessage: String {
        switch selectedPolarity {
        case .positive:
            return "Coach hasn't learned any likes yet. Chat with it more to fill this in."
        case .negative:
            return "No dislikes recorded yet."
        case .avoidAtAllCosts:
            return "No hard avoids set. Add some by re-doing the Coach interview."
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: TempoSpacing.xs) {
            Button {
                presentingRedoInterview = true
            } label: {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: "arrow.clockwise")
                    Text("Re-do Coach interview")
                        .font(.tempoCaption1)
                }
            }
            .buttonStyle(.tempoGhost)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.sm)
    }

    // MARK: - Helpers

    private var activeCount: Int { preferences.count }

    private func polarityColor(_ polarity: LearnedPreference.Polarity) -> Color {
        switch polarity {
        case .positive: return Color.tempoSignal
        case .negative: return Color.tempoTextSecondary
        case .avoidAtAllCosts: return Color.tempoError
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func delete(_ pref: LearnedPreference) {
        pref.deactivate()
        try? modelContext.save()
        editingPreference = nil
    }
}

// MARK: - EditPreferenceSheet

private struct EditPreferenceSheet: View {
    @Bindable var preference: LearnedPreference
    let onDelete: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draftText: String = ""
    @State private var draftConfidence: Double = 0
    @State private var draftScope: LearnedPreference.Scope = .always
    @State private var draftPolarity: LearnedPreference.Polarity = .positive
    @State private var confirmDelete: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextField("Preference", text: $draftText, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section("Confidence") {
                    Slider(value: $draftConfidence, in: 0...1)
                    Text("\(Int((draftConfidence * 100).rounded()))%")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Section("Scope") {
                    Picker("Scope", selection: $draftScope) {
                        ForEach(LearnedPreference.Scope.allCases, id: \.self) { scope in
                            Text(scope.displayLabel).tag(scope)
                        }
                    }
                }
                Section("Polarity") {
                    Picker("Polarity", selection: $draftPolarity) {
                        ForEach(LearnedPreference.Polarity.allCases, id: \.self) { p in
                            Text(p.displayLabel).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Save (marks as Verified)") { save() }
                    Button("This is wrong — delete", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
            .navigationTitle("Edit Preference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { hydrateDraft() }
            .alert("Delete this preference?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("I won't propose it again.")
            }
        }
    }

    private func hydrateDraft() {
        draftText = preference.text
        draftConfidence = preference.confidence
        draftScope = preference.scope
        draftPolarity = preference.polarity
    }

    private func save() {
        preference.text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        preference.scope = draftScope
        preference.polarity = draftPolarity
        preference.confidence = draftConfidence
        preference.markUserVerified()
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Display labels

extension LearnedPreference.Scope {
    var displayLabel: String {
        switch self {
        case .always: return "Always"
        case .weekday: return "Weekdays"
        case .weekend: return "Weekend"
        case .dayTypeHard: return "Hard Training Days"
        case .dayTypeRest: return "Rest Days"
        case .eventTravel: return "Travel"
        case .eventMatch: return "Match Days"
        case .seasonalSummer: return "Summer"
        }
    }
}

extension LearnedPreference.Polarity {
    var displayLabel: String {
        switch self {
        case .positive: return "Like"
        case .negative: return "Dislike"
        case .avoidAtAllCosts: return "Hard Avoid"
        }
    }
}
