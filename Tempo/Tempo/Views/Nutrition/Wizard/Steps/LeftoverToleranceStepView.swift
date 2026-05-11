//
// LeftoverToleranceStepView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

struct LeftoverToleranceStepView: View {
    @Bindable
    var coordinator: WizardCoordinator

    var body: some View {
        WizardStepScaffold(
            title: "Same meal, two days in a row?",
            subtitle: "Tells me how aggressive I can be with batch prep.",
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            onBack: coordinator.goBack,
            onPrimary: coordinator.advance,
            onCancel: coordinator.cancel
        ) {
            VStack(spacing: TempoSpacing.sm) {
                ForEach(LeftoverTolerance.allCases) { option in
                    optionRow(option)
                }
            }
        }
    }

    private func optionRow(_ option: LeftoverTolerance) -> some View {
        let selected = coordinator.intake.leftoverTolerance == option
        return Button {
            HapticManager.selection()
            coordinator.intake.leftoverTolerance = option
        } label: {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? Color.tempoSignal : Color.tempoTextTertiary)
                Text(option.displayName)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
            }
            .tempoCard()
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .stroke(selected ? Color.tempoSignal.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
    }
}
