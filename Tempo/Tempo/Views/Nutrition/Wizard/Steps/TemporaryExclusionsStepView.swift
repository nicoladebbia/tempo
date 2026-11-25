//
// TemporaryExclusionsStepView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - TemporaryExclusionsStepView

struct TemporaryExclusionsStepView: View {
    @Bindable
    var coordinator: WizardCoordinator
    @State
    private var draftInput: String = ""
    @Query(filter: #Predicate<DietaryProfile> { $0.isActive == true })
    private var profiles: [DietaryProfile]
    @Environment(\.tideMood)
    private var mood

    /// The permanent "won't eat" list (Edit setup) — always excluded.
    private var permanentExclusions: [String] {
        profiles.first?.dislikedFoods ?? []
    }

    var body: some View {
        WizardStepScaffold(
            title: String(localized: "Off the table this week."),
            subtitle: String(localized: "Not allergies — just things you're not in the mood for. Skip if nothing."),
            eyebrow: coordinator.stepCaption,
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            primaryButtonLabel: String(localized: "Next"),
            onBack: coordinator.goBack,
            onPrimary: coordinator.advance,
            onCancel: coordinator.cancel
        ) {
            VStack(alignment: .leading, spacing: Tide.s5) {
                inputRow

                if coordinator.intake.temporaryExclusions.isEmpty {
                    Label("Nothing off the table. Tap Next.", systemImage: "checkmark.circle")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    chipGrid
                }

                if !permanentExclusions.isEmpty {
                    permanentSection
                }
            }
        }
    }

    /// One soft row: the field, and a plus button inside it at the end.
    private var inputRow: some View {
        let isEmpty = draftInput.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: Tide.s2) {
            TextField("e.g. broccoli", text: $draftInput)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .submitLabel(.done)
                .onSubmit(addCurrent)
            Button {
                addCurrent()
            } label: {
                Image(systemName: "plus")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.ink)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .background(mood.accent, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)
            .opacity(isEmpty ? 0.4 : 1)
            .animation(Tide.snap, value: isEmpty)
            .accessibilityLabel("Add")
        }
        .padding(.leading, Tide.s4)
        .padding(.trailing, Tide.s1)
        .frame(minHeight: Tide.hit + Tide.s2)
        .background(Tide.fill, in: .rect(cornerRadius: Tide.tileRadius))
    }

    private var permanentSection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Always off — edit in setup")
                .tideLabel()
            FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
                ForEach(permanentExclusions, id: \.self) { food in
                    HStack(spacing: Tide.s1) {
                        Image(systemName: "lock.fill")
                            .font(Tide.label)
                            .foregroundStyle(Tide.text3)
                            .accessibilityHidden(true)
                        Text(food)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                    .padding(.horizontal, Tide.s3)
                    .frame(minHeight: Tide.s8)
                    .overlay(Capsule().strokeBorder(Tide.hairline))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(food), always off")
                }
            }
        }
        .accessibilityIdentifier("wizardPermanentExclusions")
    }

    /// Each chip is one button: tap to take it off the list.
    private var chipGrid: some View {
        FlowLayout(spacing: Tide.s2, lineSpacing: Tide.s2) {
            ForEach(coordinator.intake.temporaryExclusions, id: \.self) { food in
                Button {
                    coordinator.intake.temporaryExclusions.removeAll { $0 == food }
                    HapticManager.selection()
                } label: {
                    HStack(spacing: Tide.s2) {
                        Text(food)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                        Image(systemName: "xmark")
                            .font(Tide.label)
                            .foregroundStyle(Tide.text2)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, Tide.s4)
                    .frame(minHeight: Tide.hit)
                    .background(mood.accent.opacity(0.18), in: .capsule)
                    .overlay(Capsule().strokeBorder(mood.accent.opacity(0.5)))
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(food)")
            }
        }
    }

    private func addCurrent() {
        let trimmed = draftInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            return
        }
        let alreadyPermanent = permanentExclusions.contains { $0.lowercased() == trimmed }
        if !alreadyPermanent, !coordinator.intake.temporaryExclusions.contains(trimmed) {
            coordinator.intake.temporaryExclusions.append(trimmed)
            HapticManager.selection()
        }
        draftInput = ""
    }
}
