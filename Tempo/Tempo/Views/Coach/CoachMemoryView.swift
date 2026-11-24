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
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    @Query(filter: #Predicate<LearnedPreference> { $0.isActive })
    private var preferences: [LearnedPreference]

    @State
    private var selectedPolarity: LearnedPreference.Polarity = .positive
    @State
    private var editingPreference: LearnedPreference?
    @State
    private var presentingRedoInterview: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    header
                    polarityTabs
                    groupedList
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                footer
            }
            .tidePage()
            .navigationTitle("Coach's memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .tideCovered(editingPreference != nil || presentingRedoInterview)
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

    /// The one number of the page: how much Coach has learned.
    private var header: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            TideNumber("\(activeCount)", size: Tide.numeralL)
            Text(activeCount == 1 ? "thing Coach knows about you" : "things Coach knows about you")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Polarity tabs

    private var polarityTabs: some View {
        TideCoachChoiceChips(
            options: [
                .init(value: .positive, title: "Likes", count: count(of: .positive)),
                .init(value: .negative, title: "Dislikes", count: count(of: .negative)),
                .init(value: .avoidAtAllCosts, title: "Hard avoids", count: count(of: .avoidAtAllCosts)),
            ],
            selection: $selectedPolarity
        )
    }

    private func count(of polarity: LearnedPreference.Polarity) -> Int {
        preferences.count { $0.polarity == polarity }
    }

    // MARK: - Grouped list

    private var groupedList: some View {
        let groups = CoachMemoryGrouping.group(
            preferences: preferences,
            polarity: selectedPolarity
        )
        return LazyVStack(alignment: .leading, spacing: Tide.s5) {
            if groups.isEmpty {
                emptyState
            } else {
                ForEach(groups, id: \.scope) { group in
                    scopeSection(group)
                }
            }
        }
        .animation(Tide.snap, value: selectedPolarity)
    }

    private func scopeSection(_ group: CoachMemoryGrouping.Group) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: group.scope.displayLabel, trailing: "\(group.preferences.count)")
            GlassEffectContainer(spacing: Tide.s3) {
                VStack(spacing: Tide.s3) {
                    ForEach(group.preferences, id: \.id) { pref in
                        preferenceRow(pref)
                    }
                }
            }
        }
    }

    private func preferenceRow(_ pref: LearnedPreference) -> some View {
        Button { editingPreference = pref } label: {
            VStack(alignment: .leading, spacing: Tide.s3) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Text(pref.text)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Tide.s2)
                    if pref.needsReview {
                        TideCoachPill(title: "Review", color: Tide.streak)
                    }
                }
                HStack(spacing: Tide.s3) {
                    TideLevelBar(progress: pref.confidence, height: Tide.barSlim)
                    TideNumber(
                        "\(Int(pref.confidence * 100))", unit: "%",
                        size: TideCoach.figureSmall, relativeTo: .subheadline, weight: .semibold, color: Tide.text2
                    )
                    .fixedSize()
                }
                HStack(spacing: Tide.s2) {
                    sourcePill(pref.source)
                    Spacer(minLength: Tide.s2)
                    Text("Seen \(relativeDate(pref.lastSeenAt))")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .lineLimit(1)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCoachPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit")
    }

    private func sourcePill(_ source: LearnedPreference.Source) -> some View {
        switch source {
        case .explicit: TideCoachPill(title: "Explicit", color: Tide.fat)
        case .observed: TideCoachPill(title: "Observed", color: Tide.text2)
        case .inferred: TideCoachPill(title: "Inferred", color: Tide.text2)
        case .userVerified: TideCoachPill(title: "Verified", color: mood.accent)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Tide.s3) {
            TideStateMark(systemName: "brain.head.profile", tileSize: Tide.tileLarge - Tide.s2)
            Text(emptyStateMessage)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .tideCard(padding: Tide.s6, radius: Tide.tileRadius)
    }

    private var emptyStateMessage: String {
        switch selectedPolarity {
        case .positive:
            "Coach hasn't learned any likes yet. Chat with it more to fill this in."
        case .negative:
            "No dislikes recorded yet."
        case .avoidAtAllCosts:
            "No hard avoids set. Add some by re-doing the Coach interview."
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Button {
            presentingRedoInterview = true
        } label: {
            Label("Re-do Coach interview", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tideGlass)
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s2)
        .padding(.bottom, Tide.s2)
    }

    // MARK: - Helpers

    private var activeCount: Int {
        preferences.count
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
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    @State
    private var draftText: String = ""
    @State
    private var draftConfidence: Double = 0
    @State
    private var draftScope: LearnedPreference.Scope = .always
    @State
    private var draftPolarity: LearnedPreference.Polarity = .positive
    @State
    private var confirmDelete: Bool = false
    @State
    private var saves = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    card("Text") {
                        TextField(
                            text: $draftText,
                            prompt: Text("Preference").foregroundStyle(Tide.text3),
                            axis: .vertical
                        ) {
                            Text("Preference")
                        }
                        .lineLimit(2 ... 6)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .tint(mood.accent)
                    }

                    card("Confidence", trailing: "\(Int((draftConfidence * 100).rounded()))%") {
                        Slider(value: $draftConfidence, in: 0 ... 1)
                            .tint(mood.accent)
                            .frame(minHeight: Tide.hit)
                    }

                    card("Scope") {
                        Picker("Scope", selection: $draftScope) {
                            ForEach(LearnedPreference.Scope.allCases, id: \.self) { scope in
                                Text(scope.displayLabel).tag(scope)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(mood.accent)
                        .frame(minHeight: Tide.hit, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: Tide.s3) {
                        TideSectionLabel(title: "Polarity")
                        TideCoachChoiceChips(
                            options: LearnedPreference.Polarity.allCases.map {
                                .init(value: $0, title: $0.displayLabel)
                            },
                            selection: $draftPolarity
                        )
                    }
                    .padding(.top, Tide.s1)
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                actions
            }
            .tidePage()
            .navigationTitle("Edit preference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { hydrateDraft() }
            .sensoryFeedback(.success, trigger: saves)
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

    private func card(
        _ title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSectionLabel(title: title, trailing: trailing)
            content()
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private var actions: some View {
        VStack(spacing: Tide.s2) {
            Button("Save and mark verified") { save() }
                .buttonStyle(.tidePrimary)
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Text("This is wrong, delete")
                    .foregroundStyle(Tide.danger)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tideGlass)
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s2)
        .padding(.bottom, Tide.s2)
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
        saves += 1
        dismiss()
    }
}

// MARK: - Display labels

extension LearnedPreference.Scope {
    var displayLabel: String {
        switch self {
        case .always: "Always"
        case .weekday: "Weekdays"
        case .weekend: "Weekend"
        case .dayTypeHard: "Hard Training Days"
        case .dayTypeRest: "Rest Days"
        case .eventTravel: "Travel"
        case .eventMatch: "Match Days"
        case .seasonalSummer: "Summer"
        }
    }
}

extension LearnedPreference.Polarity {
    var displayLabel: String {
        switch self {
        case .positive: "Like"
        case .negative: "Dislike"
        case .avoidAtAllCosts: "Hard Avoid"
        }
    }
}
