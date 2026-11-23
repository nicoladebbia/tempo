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
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            primaryButtonLabel: "Generate Plan",
            onBack: coordinator.goBack,
            onPrimary: coordinator.submit,
            onCancel: coordinator.cancel
        ) {
            VStack(spacing: 0) {
                summaryRow(
                    label: "Cookable days",
                    value: "\(coordinator.intake.cookableDaysThisWeek)/7"
                )
                if coordinator.snapshot.hasWhoop {
                    divider
                    summaryRow(
                        label: "Recovery skew",
                        value: coordinator.intake.recoveryAdjusted ? "On" : "Off"
                    )
                }
                if !coordinator.intake.temporaryExclusions.isEmpty {
                    divider
                    summaryRow(
                        label: "Excluding",
                        value: coordinator.intake.temporaryExclusions.joined(separator: ", ")
                    )
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private var divider: some View {
        Divider().overlay(Tide.hairline)
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
        .padding(.vertical, Tide.s3)
        .accessibilityElement(children: .combine)
    }
}
