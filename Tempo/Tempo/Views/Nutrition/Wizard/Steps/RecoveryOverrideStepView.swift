//
// RecoveryOverrideStepView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

struct RecoveryOverrideStepView: View {
    @Bindable
    var coordinator: WizardCoordinator

    var body: some View {
        WizardStepScaffold(
            title: "Adjust around training?",
            subtitle: subtitleText,
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            onBack: coordinator.goBack,
            onPrimary: coordinator.advance,
            onCancel: coordinator.cancel
        ) {
            VStack(spacing: TempoSpacing.md) {
                if let score = coordinator.snapshot.whoop?.recoveryScore {
                    recoveryBadge(score: score)
                }

                Toggle(isOn: $coordinator.intake.recoveryAdjusted) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skew fueling to training load")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text("More fuel on training days, lighter on rest days.")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                .tint(Color.tempoSignal)
                .tempoCard()
            }
        }
    }

    private var subtitleText: String {
        if let score = coordinator.snapshot.whoop?.recoveryScore {
            return "Yesterday's recovery: \(Int(score)). Want the plan to lean into that?"
        }
        return "Adjust calorie distribution based on training intensity this week?"
    }

    private func recoveryBadge(score: Double) -> some View {
        let color: Color = if score >= 67 {
            .tempoSuccess
        } else if score >= 34 {
            .tempoWarning
        } else {
            .tempoError
        }
        return HStack(spacing: TempoSpacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text("Whoop recovery yesterday")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            Text("\(Int(score))")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .tempoCard()
    }
}
