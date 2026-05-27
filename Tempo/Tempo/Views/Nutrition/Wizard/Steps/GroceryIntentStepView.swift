//
// GroceryIntentStepView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftData
import SwiftUI

struct GroceryIntentStepView: View {
    @Bindable
    var coordinator: WizardCoordinator
    @Environment(\.modelContext)
    private var modelContext
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
            // Source-of-truth order:
            //   1. The in-memory intake (already set in this regen flow)
            //   2. UserSettings (persisted across regens — the bug fix)
            // Previously only #1 was checked, so every regen the user had
            // to re-type the budget cap and store list.
            if let cap = coordinator.intake.groceryIntent?.budgetCapUSD {
                budgetText = "\(cap)"
            } else if let settings = loadSettings(), let cap = settings.groceryBudgetCapUSD {
                budgetText = "\(cap)"
            }
            if let stores = coordinator.intake.groceryIntent?.preferredStores, !stores.isEmpty {
                storesText = stores.joined(separator: ", ")
            } else if let settings = loadSettings(), !settings.groceryPreferredStores.isEmpty {
                storesText = settings.groceryPreferredStores.joined(separator: ", ")
            }
        }
    }

    private func commitAndAdvance() {
        let parsedCap = Int(budgetText.trimmingCharacters(in: .whitespaces))
        let parsedStores = storesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var current = coordinator.intake.groceryIntent ?? GroceryIntent(
            willShopThisWeek: true,
            budgetCapUSD: nil,
            preferredStores: []
        )
        current.budgetCapUSD = parsedCap
        current.preferredStores = parsedStores
        coordinator.intake.groceryIntent = current

        // Persist to UserSettings so the next regen pre-fills the wizard.
        if let settings = loadSettings() {
            settings.groceryBudgetCapUSD = parsedCap
            settings.groceryPreferredStores = parsedStores
            try? modelContext.save()
        }

        coordinator.advance()
    }

    /// Singleton-ish UserSettings lookup. Returns nil before the first
    /// settings row exists (early onboarding), which is fine — the
    /// wizard just no-ops the persistence and falls back to the
    /// in-memory intake.
    private func loadSettings() -> UserSettings? {
        let descriptor = FetchDescriptor<UserSettings>()
        return (try? modelContext.fetch(descriptor))?.first
    }
}
