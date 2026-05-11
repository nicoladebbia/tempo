//
// EatingWindowStepView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

struct EatingWindowStepView: View {
    @Bindable
    var coordinator: WizardCoordinator

    var body: some View {
        WizardStepScaffold(
            title: "First meal, last meal.",
            subtitle: "I anchor the plan around your eating window. Honesty pays off here.",
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            primaryButtonEnabled: coordinator.intake.eatingWindow.isValid,
            onBack: coordinator.goBack,
            onPrimary: coordinator.advance,
            onCancel: coordinator.cancel
        ) {
            VStack(spacing: TempoSpacing.md) {
                row(
                    label: "First meal",
                    selection: Binding(
                        get: { coordinator.intake.eatingWindow.firstMealHour },
                        set: { coordinator.intake.eatingWindow.firstMealHour = $0 }
                    ),
                    range: 4 ... 14
                )
                row(
                    label: "Last meal",
                    selection: Binding(
                        get: { coordinator.intake.eatingWindow.lastMealHour },
                        set: { coordinator.intake.eatingWindow.lastMealHour = $0 }
                    ),
                    range: 16 ... 23
                )
            }
        }
    }

    private func row(label: String, selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Picker(label, selection: selection) {
                ForEach(range, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour))
                        .tag(hour)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.tempoViolet)
        }
        .tempoCard()
    }
}
