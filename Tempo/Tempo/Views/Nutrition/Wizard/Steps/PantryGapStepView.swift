//
// PantryGapStepView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

struct PantryGapStepView: View {
    @Bindable
    var coordinator: WizardCoordinator

    var body: some View {
        WizardStepScaffold(
            title: "Pantry status.",
            subtitle: subtitleText,
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            primaryButtonEnabled: coordinator.intake.groceryIntent != nil,
            onBack: coordinator.goBack,
            onPrimary: coordinator.advance,
            onCancel: coordinator.cancel
        ) {
            VStack(spacing: TempoSpacing.sm) {
                optionRow(
                    title: "I'm doing a grocery run.",
                    subtitle: "Plan can include fresh purchases.",
                    icon: "cart.fill",
                    selected: coordinator.intake.groceryIntent?.willShopThisWeek == true
                ) {
                    var current = coordinator.intake.groceryIntent ?? GroceryIntent(
                        willShopThisWeek: true,
                        budgetCapUSD: nil,
                        preferredStores: []
                    )
                    current.willShopThisWeek = true
                    coordinator.intake.groceryIntent = current
                }
                optionRow(
                    title: "Work from what I already have.",
                    subtitle: "Plan stays within current pantry + small additions.",
                    icon: "shippingbox.fill",
                    selected: coordinator.intake.groceryIntent?.willShopThisWeek == false
                ) {
                    coordinator.intake.groceryIntent = GroceryIntent(
                        willShopThisWeek: false,
                        budgetCapUSD: nil,
                        preferredStores: []
                    )
                }
            }
        }
    }

    private var subtitleText: String {
        let count = coordinator.snapshot.pantry.itemCount
        if count == 0 {
            return "Your pantry shows zero items. Need a grocery run, or working from elsewhere?"
        }
        return "Pantry shows \(count) items but hasn't been updated lately. Still accurate?"
    }

    private func optionRow(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            HStack(alignment: .top, spacing: TempoSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Color.tempoSignal : Color.tempoTextTertiary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(subtitle)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Color.tempoSignal : Color.tempoTextTertiary)
            }
            .tempoCard()
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                    .stroke(selected ? Color.tempoSignal.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
    }
}
