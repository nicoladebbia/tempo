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

    @Environment(\.tideMood)
    private var mood

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
            VStack(spacing: Tide.s3) {
                if let score = coordinator.snapshot.whoop?.recoveryScore {
                    recoveryBadge(score: score)
                }

                Toggle(isOn: $coordinator.intake.recoveryAdjusted) {
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text("Skew fueling to training load")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("More fuel on training days, lighter on rest days.")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(mood.accent)
                .frame(minHeight: Tide.hit)
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
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
            Tide.good
        } else if score >= 34 {
            Tide.warn
        } else {
            Tide.danger
        }
        return HStack(spacing: Tide.s3) {
            Circle()
                .fill(color)
                .frame(width: Tide.s2, height: Tide.s2)
                .accessibilityHidden(true)
            Text("Whoop recovery yesterday")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tide.s2)
            TideNumber("\(Int(score))", size: Tide.numeralS, color: color)
        }
        .accessibilityElement(children: .combine)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }
}
