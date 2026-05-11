//
// TemporaryExclusionsStepView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

// MARK: - TemporaryExclusionsStepView

struct TemporaryExclusionsStepView: View {
    @Bindable
    var coordinator: WizardCoordinator
    @State
    private var draftInput: String = ""

    var body: some View {
        WizardStepScaffold(
            title: "Off the table this week.",
            subtitle: "Not allergies — just things you're not in the mood for. Skip if nothing.",
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            primaryButtonLabel: "Next",
            onBack: coordinator.goBack,
            onPrimary: coordinator.advance,
            onCancel: coordinator.cancel
        ) {
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                HStack(spacing: TempoSpacing.sm) {
                    TextField("e.g. broccoli", text: $draftInput)
                        .font(.tempoBody)
                        .padding(TempoSpacing.md)
                        .background(Color.tempoSurfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                        .onSubmit(addCurrent)

                    Button {
                        addCurrent()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.tempoTextInverse)
                            .frame(width: 44, height: 44)
                            .background(Color.tempoSignal)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                    }
                    .disabled(draftInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !coordinator.intake.temporaryExclusions.isEmpty {
                    chipGrid
                }
            }
        }
    }

    private var chipGrid: some View {
        FlowLayout(spacing: TempoSpacing.xs, lineSpacing: TempoSpacing.xs) {
            ForEach(coordinator.intake.temporaryExclusions, id: \.self) { food in
                HStack(spacing: 6) {
                    Text(food)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Button {
                        coordinator.intake.temporaryExclusions.removeAll { $0 == food }
                        HapticManager.selection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .padding(.horizontal, TempoSpacing.sm)
                .padding(.vertical, 6)
                .background(Color.tempoSurfaceElevated)
                .clipShape(Capsule())
            }
        }
    }

    private func addCurrent() {
        let trimmed = draftInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            return
        }
        if !coordinator.intake.temporaryExclusions.contains(trimmed) {
            coordinator.intake.temporaryExclusions.append(trimmed)
            HapticManager.selection()
        }
        draftInput = ""
    }
}
