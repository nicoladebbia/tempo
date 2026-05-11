//
// GroceryIntentStepView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

struct GroceryIntentStepView: View {
    @Bindable
    var coordinator: WizardCoordinator
    @State
    private var budgetText: String = ""
    @State
    private var storesText: String = ""

    var body: some View {
        WizardStepScaffold(
            title: "Grocery limits.",
            subtitle: "Budget cap and preferred stores. Skip what doesn't apply.",
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            onBack: coordinator.goBack,
            onPrimary: commitAndAdvance,
            onCancel: coordinator.cancel
        ) {
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("BUDGET CAP (USD)")
                        .font(.tempoModuleTag)
                        .tracking(TempoTracking.drillLabel)
                        .foregroundStyle(Color.tempoTextTertiary)
                    TextField("e.g. 75", text: $budgetText)
                        .keyboardType(.numberPad)
                        .font(.tempoBody)
                        .padding(TempoSpacing.md)
                        .background(Color.tempoSurfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                }

                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("PREFERRED STORES")
                        .font(.tempoModuleTag)
                        .tracking(TempoTracking.drillLabel)
                        .foregroundStyle(Color.tempoTextTertiary)
                    TextField("e.g. Publix, Trader Joe's", text: $storesText)
                        .font(.tempoBody)
                        .padding(TempoSpacing.md)
                        .background(Color.tempoSurfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                }
            }
        }
        .onAppear {
            if let cap = coordinator.intake.groceryIntent?.budgetCapUSD {
                budgetText = "\(cap)"
            }
            if let stores = coordinator.intake.groceryIntent?.preferredStores, !stores.isEmpty {
                storesText = stores.joined(separator: ", ")
            }
        }
    }

    private func commitAndAdvance() {
        var current = coordinator.intake.groceryIntent ?? GroceryIntent(
            willShopThisWeek: true,
            budgetCapUSD: nil,
            preferredStores: []
        )
        current.budgetCapUSD = Int(budgetText.trimmingCharacters(in: .whitespaces))
        current.preferredStores = storesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        coordinator.intake.groceryIntent = current
        coordinator.advance()
    }
}
