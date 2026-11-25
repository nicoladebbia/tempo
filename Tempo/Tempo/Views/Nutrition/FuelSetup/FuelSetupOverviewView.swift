//
// FuelSetupOverviewView.swift
// Tempo
//
// "Your fuel profile": one card per section with a one-line summary. Tap a
// card to edit just that section in its own onboarding-style flow, with its
// own Save. You, Goal and Meals are required (flagged "Still needed" until
// answered); every other section is optional, reads a neutral "Not set —
// we'll use sensible defaults" and can be skipped. A "Finish setup" card walks
// through whatever is left, and a sticky bar saves everything that changed.
// Body stats from Apple Health show read-only with a badge.
//

import SwiftUI

struct FuelSetupOverviewView: View {
    let draft: FuelSetupDraft
    /// The draft as last stored; a section that differs shows "Unsaved".
    let saved: FuelSetupDraft
    let locked: Set<FuelBodyField>
    let unit: WeightUnit
    /// Optional sections already saved or skipped (not offered again).
    var reviewed: Set<FuelSetupSection> = []
    /// Title of the bottom button (save everything and go on); nil hides it.
    let primaryActionTitle: String?
    /// Plan generation is waiting on required sections: say which, and offer to finish them.
    var blockedMessage: String?
    var onOpen: (FuelSetupSection) -> Void
    var onFinish: ([FuelSetupSection]) -> Void = { _ in }
    var onSkip: (FuelSetupSection) -> Void = { _ in }
    var onTalkAgain: () -> Void
    var onSaveAll: () -> Void

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .headline)
    private var iconBox: CGFloat = Tide.icon + Tide.s2

    private var remaining: [FuelSetupSection] {
        draft.remainingSections(reviewed: reviewed)
    }

    private var dirtySections: [FuelSetupSection] {
        FuelSetupSection.allCases.filter { draft.isDirty($0, comparedTo: saved) }
    }

    private var missing: [FuelSetupSection] {
        draft.incompleteSections
    }

    /// Sections that have an answer: nothing missing, and an optional one is not left at its defaults.
    private var doneCount: Int {
        FuelSetupSection.allCases.filter { draft.missingFields(in: $0).isEmpty && !draft.isUnset($0) }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s5) {
                header
                if !remaining.isEmpty {
                    finishCard
                }
                FuelRowGroup(title: "Needed for your plan", trailing: requiredTrailing) {
                    ForEach(FuelSetupSection.allCases.filter(\.isRequired)) { section in
                        row(section)
                    }
                }
                FuelRowGroup(title: "Optional") {
                    ForEach(FuelSetupSection.allCases.filter { !$0.isRequired }) { section in
                        row(section)
                    }
                }
                talkCard
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let blockedMessage {
                blockedBar(blockedMessage)
            } else if let primaryActionTitle {
                saveAllBar(primaryActionTitle)
            }
        }
        .tidePage()
    }

    // MARK: - Pieces

    /// The ring counts the sections that have an answer; the title and line stay as they were.
    private var header: some View {
        FuelProgressHero(
            done: doneCount,
            total: FuelSetupSection.allCases.count,
            title: "Your fuel profile",
            caption: "Tap a section to change it. Each one saves on its own, or save everything at the bottom.",
            tint: missing.isEmpty ? Tide.good : nil
        )
        .padding(.vertical, Tide.s2)
    }

    /// "1 left" over the required group while something blocks the plan.
    private var requiredTrailing: String? {
        missing.isEmpty ? nil : "\(missing.count) left"
    }

    /// "Finish setup · 3 left": chains through what's missing, required first.
    /// Accent-tinted glass, not a fill: the one filled button on this screen is the bar at the bottom.
    private var finishCard: some View {
        let list = remaining
        let hasRequired = list.contains(where: \.isRequired)
        return Button {
            HapticManager.lightImpact()
            onFinish(list)
        } label: {
            HStack(spacing: Tide.s3) {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("Finish setup · \(list.count) left")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(hasRequired
                        ? "Next: \(list[0].title). Needed for your plan."
                        : "Next: \(list[0].title). All optional, skip any.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(Tide.headline)
                    .foregroundStyle(mood.accent)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Tide.hit)
            .padding(Tide.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(mood.accent.opacity(0.28)).interactive(), in: .rect(cornerRadius: Tide.cardRadius))
            .contentShape(.rect(cornerRadius: Tide.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fuelSetupFinish")
    }

    /// A quiet way back to the talk step: a line of glass, not a card of its own.
    private var talkCard: some View {
        Button(action: onTalkAgain) {
            HStack(spacing: Tide.s3) {
                Image(systemName: "mic.fill")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(mood.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("Tell me more")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                    Text("Talk or type. I fill in the sections for you.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Tide.hit)
            .padding(.horizontal, Tide.s4)
            .padding(.vertical, Tide.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .rect(cornerRadius: Tide.tileRadius))
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(FuelPressStyle())
        .accessibilityIdentifier("fuelSetupTalkAgain")
    }

    /// One section: its icon, name, what is saved in it, and where it stands
    /// (needed, unsaved, done). Optional sections that are still at their
    /// defaults can be skipped from the row.
    private func row(_ section: FuelSetupSection) -> some View {
        let isMissing = !draft.missingFields(in: section).isEmpty
        let isDirty = draft.isDirty(section, comparedTo: saved)
        let isUnset = draft.isUnset(section)
        let canSkip = isUnset && !reviewed.contains(section)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return layout {
            Button {
                HapticManager.selection()
                onOpen(section)
            } label: {
                HStack(alignment: .top, spacing: Tide.s3) {
                    TideIconTile(
                        systemName: section.icon,
                        tint: isMissing ? Tide.warn : (isUnset ? Tide.text2 : mood.accent),
                        size: iconBox
                    )
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        Text(section.title)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if isMissing || isDirty {
                            HStack(spacing: Tide.s1) {
                                if isMissing {
                                    FuelPill(text: "Needed", color: Tide.warn)
                                }
                                if isDirty {
                                    FuelPill(text: section == .you && !locked.isEmpty ? "Update" : "Unsaved", color: mood.accent)
                                }
                            }
                            .fixedSize()
                        }
                        Text(draft.summary(for: section, unit: unit))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if section == .you, !locked.isEmpty {
                            HealthBadge()
                                .padding(.top, Tide.hair)
                        }
                    }
                    Spacer(minLength: 0)
                    if !canSkip {
                        Image(systemName: isMissing || isUnset ? "chevron.right" : "checkmark.circle.fill")
                            .font(isMissing || isUnset ? Tide.caption : Tide.headline)
                            .foregroundStyle(isMissing || isUnset ? Tide.text3 : Tide.good)
                            .frame(minHeight: iconBox)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: Tide.hit)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("fuelSection.\(section.rawValue)")
            if canSkip {
                Button {
                    HapticManager.selection()
                    onSkip(section)
                } label: {
                    Text("Optional · Skip")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .padding(.horizontal, Tide.s2)
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip \(section.title)")
                .accessibilityIdentifier("fuelSkip.\(section.rawValue)")
            }
        }
        .animation(Tide.snap, value: isMissing)
    }

    /// A glass bar floating at the bottom: the main button of the screen.
    private func bottomBar(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .tideCard(padding: Tide.s4)
            .padding(.horizontal, Tide.s4)
            .padding(.bottom, Tide.s2)
    }

    private func saveAllBar(_ title: String) -> some View {
        bottomBar {
            Button(action: onSaveAll) {
                Text(title)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tidePrimary)
            .accessibilityIdentifier("fuelSetupSave")
        }
    }

    /// Plan generation can't go on: one message naming what's missing, one button.
    private func blockedBar(_ message: String) -> some View {
        bottomBar {
            VStack(spacing: Tide.s3) {
                Text(message)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("fuelSetupBlocked")
                Button {
                    onFinish(draft.incompleteSections)
                } label: {
                    Text("Finish what's missing")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tidePrimary)
                .accessibilityIdentifier("fuelSetupFinishRequired")
            }
        }
    }
}
