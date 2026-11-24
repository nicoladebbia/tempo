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
    @Environment(\.dynamicTypeSize)
    private var typeSize

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
                .environment(\.tideInsidePage, false)
        }
        .sheet(isPresented: $presentingRedoInterview) {
            CoachInterviewView { _ in
                presentingRedoInterview = false
            }
            .environment(\.tideInsidePage, false)
        }
    }

    // MARK: - Header

    /// The one number of the page: how much Coach has learned, and how it
    /// splits between likes, dislikes and hard avoids.
    private var header: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            VStack(alignment: .leading, spacing: Tide.s1) {
                TideNumber("\(activeCount)", size: Tide.numeralL)
                Text(activeCount == 1 ? "thing Coach knows about you" : "things Coach knows about you")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
            }
            .accessibilityElement(children: .combine)
            if activeCount > 0 {
                TideCoachSegmentBar(
                    segments: LearnedPreference.Polarity.allCases.enumerated().map { index, polarity in
                        .init(id: index, value: count(of: polarity), color: polarity.tint)
                    }
                )
                FlowLayout(spacing: Tide.s4, lineSpacing: Tide.s1) {
                    ForEach(LearnedPreference.Polarity.allCases, id: \.self) { polarity in
                        HStack(spacing: Tide.s1) {
                            Circle().fill(polarity.tint).frame(width: Tide.s2, height: Tide.s2)
                            Text("\(count(of: polarity)) \(polarity.pluralLabel)")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s5, radius: Tide.cardRadius)
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
            HStack(spacing: Tide.s2) {
                Image(systemName: group.scope.symbol)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
                TideSectionLabel(title: group.scope.displayLabel, trailing: "\(group.preferences.count)")
            }
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
            HStack(alignment: .top, spacing: Tide.s3) {
                if !typeSize.isAccessibilitySize {
                    TideIconTile(systemName: pref.polarity.symbol, tint: pref.polarity.tint, size: Tide.tile)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
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
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCoachPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit")
    }

    private func sourcePill(_ source: LearnedPreference.Source) -> some View {
        TideCoachPill(title: source.pillTitle, color: source.pillColor(accent: mood.accent))
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
                    // Where this came from; the tile follows the polarity you pick.
                    HStack(spacing: Tide.s3) {
                        TideIconTile(
                            systemName: draftPolarity.symbol,
                            tint: draftPolarity.tint,
                            size: Tide.tileLarge - Tide.s2
                        ).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        VStack(alignment: .leading, spacing: Tide.s1) {
                            TideCoachPill(
                                title: preference.source.pillTitle,
                                color: preference.source.pillColor(accent: mood.accent)
                            )
                            Text("Seen \(preference.lastSeenAt.formatted(.relative(presentation: .named)))")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }
                        Spacer(minLength: 0)
                    }
                    .animation(Tide.snap, value: draftPolarity)
                    .accessibilityElement(children: .combine)

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

extension LearnedPreference.Scope {
    /// A symbol for the group heading.
    var symbol: String {
        switch self {
        case .always: "infinity"
        case .weekday: "briefcase.fill"
        case .weekend: "sun.max.fill"
        case .dayTypeHard: "figure.strengthtraining.traditional"
        case .dayTypeRest: "bed.double.fill"
        case .eventTravel: "airplane"
        case .eventMatch: "sportscourt.fill"
        case .seasonalSummer: "sun.haze.fill"
        }
    }
}

extension LearnedPreference.Polarity {
    /// Likes read green, dislikes amber, hard avoids red.
    var tint: Color {
        switch self {
        case .positive: Tide.good
        case .negative: Tide.warn
        case .avoidAtAllCosts: Tide.danger
        }
    }

    var symbol: String {
        switch self {
        case .positive: "hand.thumbsup.fill"
        case .negative: "hand.thumbsdown.fill"
        case .avoidAtAllCosts: "nosign"
        }
    }

    /// "likes", "dislikes", "hard avoids": how the page counts them.
    var pluralLabel: String {
        switch self {
        case .positive: "likes"
        case .negative: "dislikes"
        case .avoidAtAllCosts: "hard avoids"
        }
    }
}

private extension LearnedPreference.Source {
    var pillTitle: String {
        switch self {
        case .explicit: "Explicit"
        case .observed: "Observed"
        case .inferred: "Inferred"
        case .userVerified: "Verified"
        }
    }

    func pillColor(accent: Color) -> Color {
        switch self {
        case .explicit: Tide.fat
        case .observed,
             .inferred: Tide.text2
        case .userVerified: accent
        }
    }
}
