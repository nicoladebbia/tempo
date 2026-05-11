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
            VStack(spacing: TempoSpacing.sm) {
                summaryRow(
                    label: "Cookable days",
                    value: "\(coordinator.intake.cookableDaysThisWeek)/7"
                )
                summaryRow(
                    label: "Leftovers",
                    value: coordinator.intake.leftoverTolerance.displayName
                )
                summaryRow(
                    label: "Eating window",
                    value: "\(formatHour(coordinator.intake.eatingWindow.firstMealHour)) – \(formatHour(coordinator.intake.eatingWindow.lastMealHour))"
                )
                if let grocery = coordinator.intake.groceryIntent {
                    summaryRow(
                        label: "Grocery",
                        value: grocery.willShopThisWeek
                            ? (grocery.budgetCapUSD.map { "Shop, $\($0) cap" } ?? "Shop, no cap")
                            : "From pantry"
                    )
                }
                if coordinator.snapshot.hasWhoop {
                    summaryRow(
                        label: "Recovery skew",
                        value: coordinator.intake.recoveryAdjusted ? "On" : "Off"
                    )
                }
                if !coordinator.intake.temporaryExclusions.isEmpty {
                    summaryRow(
                        label: "Excluding",
                        value: coordinator.intake.temporaryExclusions.joined(separator: ", ")
                    )
                }
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextTertiary)
            Spacer(minLength: TempoSpacing.md)
            Text(value)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.trailing)
        }
        .tempoCard()
    }

    private func formatHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
