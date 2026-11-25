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
    @ScaledMetric(relativeTo: .title)
    private var ring = Tide.fuelHeroRing

    var body: some View {
        WizardStepScaffold(
            title: "Adjust around training?",
            subtitle: subtitleText,
            eyebrow: coordinator.stepCaption,
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

    /// Yesterday's Whoop recovery as a lit ring: the number is the hero of this step.
    private func recoveryBadge(score: Double) -> some View {
        let color: Color
        let band: String
        if score >= 67 {
            color = Tide.good
            band = "Green"
        } else if score >= 34 {
            color = Tide.warn
            band = "Yellow"
        } else {
            color = Tide.danger
            band = "Red"
        }
        return HStack(spacing: Tide.s4) {
            ZStack {
                TideRing(progress: min(max(score / 100, 0), 1), color: color, lineWidth: Tide.fuelHeroRingLine)
                TideNumber("\(Int(score))", size: Tide.numeralS, relativeTo: .headline, color: color)
            }
            .frame(width: ring, height: ring)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text("Whoop recovery yesterday")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(band)
                    .font(Tide.caption)
                    .foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }
}
