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

    private var remaining: [FuelSetupSection] {
        draft.remainingSections(reviewed: reviewed)
    }

    private var dirtySections: [FuelSetupSection] {
        FuelSetupSection.allCases.filter { draft.isDirty($0, comparedTo: saved) }
    }

    private var missing: [FuelSetupSection] {
        draft.incompleteSections
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                header
                if !remaining.isEmpty {
                    finishCard
                }
                talkCard
                VStack(spacing: TempoSpacing.sm) {
                    ForEach(FuelSetupSection.allCases) { section in
                        card(section)
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.sm)
            .padding(.bottom, TempoSpacing.xl)
        }
        .safeAreaInset(edge: .bottom) {
            if let blockedMessage {
                blockedBar(blockedMessage)
            } else if let primaryActionTitle {
                saveAllBar(primaryActionTitle)
            }
        }
        .background(Color.tempoBgPrimary)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("YOUR FUEL PROFILE")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Tap a section to change it. Each one saves on its own, or save everything at the bottom.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    /// "Finish setup · 3 left": chains through what's missing, required first.
    private var finishCard: some View {
        let list = remaining
        let hasRequired = list.contains(where: \.isRequired)
        return Button {
            HapticManager.lightImpact()
            onFinish(list)
        } label: {
            HStack(spacing: TempoSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish setup · \(list.count) left")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextInverse)
                    Text(hasRequired
                        ? "Next: \(list[0].title). Needed for your plan."
                        : "Next: \(list[0].title). All optional, skip any.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextInverse.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.tempoTextInverse)
            }
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Color.tempoSignal)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fuelSetupFinish")
    }

    private var talkCard: some View {
        Button(action: onTalkAgain) {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.tempoTextInverse)
                    .frame(width: 36, height: 36)
                    .background(Color.tempoSignal)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tell me more")
                        .font(.tempoBodyBold)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("Talk or type. I fill in the sections for you.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tempoSignal.opacity(TempoOpacity.o10))
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fuelSetupTalkAgain")
    }

    private func card(_ section: FuelSetupSection) -> some View {
        let isMissing = !draft.missingFields(in: section).isEmpty
        let isDirty = draft.isDirty(section, comparedTo: saved)
        let isUnset = draft.isUnset(section)
        let canSkip = isUnset && !reviewed.contains(section)
        return HStack(spacing: TempoSpacing.sm) {
            Button {
                HapticManager.selection()
                onOpen(section)
            } label: {
                HStack(spacing: TempoSpacing.md) {
                    Image(systemName: section.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isMissing ? Color.tempoWarning : Color.tempoSignal)
                        .frame(width: 36, height: 36)
                        .background(Color.tempoBgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: TempoSpacing.sm) {
                            Text(section.title)
                                .font(.tempoBodyBold)
                                .foregroundStyle(Color.tempoTextPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            if isMissing {
                                chip("Needed", color: .tempoWarning)
                            }
                            if isDirty {
                                chip(section == .you && !locked.isEmpty ? "Update" : "Unsaved", color: .tempoInfo)
                            }
                        }
                        Text(draft.summary(for: section, unit: unit))
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if section == .you, !locked.isEmpty {
                            HealthBadge()
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                    if !canSkip {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("fuelSection.\(section.rawValue)")
            if canSkip {
                Button {
                    HapticManager.selection()
                    onSkip(section)
                } label: {
                    Text("Optional · Skip")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .padding(.horizontal, TempoSpacing.sm)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip \(section.title)")
                .accessibilityIdentifier("fuelSkip.\(section.rawValue)")
            }
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                .stroke(isMissing ? Color.tempoWarning.opacity(0.6) : Color.tempoBorder, lineWidth: isMissing ? 1.5 : 0.5)
        )
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.tempoCaption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, TempoSpacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(TempoOpacity.o15))
            .clipShape(Capsule())
            .fixedSize()
    }

    private func saveAllBar(_ title: String) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            Button(action: onSaveAll) {
                Text(title)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoPrimary)
            .accessibilityIdentifier("fuelSetupSave")
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoBgPrimary)
    }

    /// Plan generation can't go on: one message naming what's missing, one button.
    private func blockedBar(_ message: String) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            Text(message)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("fuelSetupBlocked")
            Button {
                onFinish(draft.incompleteSections)
            } label: {
                Text("Finish what's missing")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoPrimary)
            .accessibilityIdentifier("fuelSetupFinishRequired")
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoBgPrimary)
    }
}
