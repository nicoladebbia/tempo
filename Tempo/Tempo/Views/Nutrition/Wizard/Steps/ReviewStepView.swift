//
// ReviewStepView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

struct ReviewStepView: View {
    @Bindable
    var coordinator: WizardCoordinator

    var body: some View {
        WizardStepScaffold(
            title: "Lock it in.",
            subtitle: "Final read. Tap Generate when ready.",
            eyebrow: coordinator.stepCaption,
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            primaryButtonLabel: "Generate Plan",
            onBack: coordinator.goBack,
            onPrimary: coordinator.submit,
            onCancel: coordinator.cancel
        ) {
            VStack(alignment: .leading, spacing: Tide.s5) {
                // What the plan will be built on: the cook count leads.
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("Cookable days").tideLabel()
                    TideNumber("\(coordinator.intake.cookableDaysThisWeek)", unit: "of 7 days", size: Tide.numeralL)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                FuelRowGroup(title: "Also this week") {
                    summaryRow(
                        label: "Excluding",
                        value: coordinator.intake.temporaryExclusions.isEmpty
                            ? "Nothing"
                            : coordinator.intake.temporaryExclusions.joined(separator: ", ")
                    )
                    if coordinator.snapshot.hasWhoop {
                        summaryRow(
                            label: "Recovery skew",
                            value: coordinator.intake.recoveryAdjusted ? "On" : "Off"
                        )
                    }
                }
            }
        }
    }

    /// Label left, value right; on huge text sizes the value drops under the label.
    private func summaryRow(label: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                Text(label)
                    .tideLabel()
                Spacer(minLength: Tide.s3)
                Text(value)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(label)
                    .tideLabel()
                Text(value)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
