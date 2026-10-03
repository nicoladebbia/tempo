//
// FuelSetupOverviewView.swift
// Tempo
//
// "Your fuel profile": one card per section with a one-line summary. Tap a
// card to edit just that section in its own onboarding-style flow, with its
// own Save. Sections the planner can't work without are flagged "Still
// needed"; body stats from Apple Health show read-only with a badge.
//

import SwiftUI

struct FuelSetupOverviewView: View {
    let draft: FuelSetupDraft
    /// The draft as last stored; a section that differs shows "Unsaved".
    let saved: FuelSetupDraft
    let locked: Set<FuelBodyField>
    let unit: WeightUnit
    /// Title of the bottom button (save everything and go on); nil hides it.
    let primaryActionTitle: String?
    var onOpen: (FuelSetupSection) -> Void
    var onTalkAgain: () -> Void
    var onSaveAll: () -> Void

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
            if let primaryActionTitle {
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
            if missing.isEmpty {
                Text("Tap a section to change it. Each one saves on its own.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                Label("Still needed: \(missing.map(\.title).joined(separator: ", "))", systemImage: "exclamationmark.circle.fill")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        return Button {
            HapticManager.selection()
            onOpen(section)
        } label: {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: section.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isMissing ? Color.tempoWarning : Color.tempoSignal)
                    .frame(width: 40, height: 40)
                    .background(Color.tempoBgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: TempoSpacing.sm) {
                        Text(section.title)
                            .font(.tempoBodyBold)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if isMissing {
                            chip("Still needed", color: .tempoWarning)
                        } else if isDirty {
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .stroke(isMissing ? Color.tempoWarning.opacity(0.6) : Color.tempoBorder, lineWidth: isMissing ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fuelSection.\(section.rawValue)")
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
}
