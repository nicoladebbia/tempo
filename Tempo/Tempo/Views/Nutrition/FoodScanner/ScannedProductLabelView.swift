//
// ScannedProductLabelView.swift
// Tempo
//
// Label mode after a barcode scan: the nutrition facts we hold for the product
// just scanned (per 100 g and per serving), its ingredients and allergens. If
// the label is missing or looks wrong, "Photograph the label" re-reads it for
// THIS product (same barcode) instead of starting an unrelated one.
//

import SwiftUI

struct ScannedProductLabelView: View {
    let product: FoodProduct
    let catalog: FoodCatalog
    let onUpdated: (FoodProduct) -> Void
    let onScanAnother: () -> Void

    @State
    private var showEditor = false

    private var hasLabel: Bool {
        product.per100g.hasCoreMacros
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                header
                if hasLabel {
                    factsCard
                } else {
                    missingCard
                }
                if let ingredients = product.ingredientsText, !ingredients.isEmpty {
                    textCard("INGREDIENTS", ingredients)
                }
                if !product.allergens.isEmpty {
                    textCard("ALLERGENS", product.allergens.map { $0.replacingOccurrences(of: "-", with: " ").capitalized }.joined(separator: ", "))
                }
                actions
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.sm)
            .padding(.bottom, TempoSpacing.xxxxl)
        }
        .background(Color.tempoBgPrimary)
        .accessibilityIdentifier("scannedProductLabel")
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                AddProductView(barcode: product.barcode, catalog: catalog, prefill: product) { updated in
                    showEditor = false
                    onUpdated(updated)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showEditor = false }
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            Text(product.displayName)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            if let barcode = product.barcode {
                Text("Barcode \(barcode)")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
    }

    private var factsCard: some View {
        let per100 = product.per100g
        let serving = product.servingGrams.flatMap { $0 > 0 && $0 != 100 ? $0 : nil }
        let perServing = serving.map { product.nutrients(forGrams: $0) }
        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("NUTRITION FACTS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            Grid(alignment: .leading, horizontalSpacing: TempoSpacing.md, verticalSpacing: TempoSpacing.sm) {
                GridRow {
                    Text("")
                    Text("100 \(product.unit)").gridColumnAlignment(.trailing)
                    if let serving {
                        Text("\(FoodProductView.format(serving)) \(product.unit)").gridColumnAlignment(.trailing)
                    }
                }
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
                Divider()
                row("Calories", per100.kcal, perServing?.kcal, unit: "kcal", showServing: serving != nil)
                row("Fat", per100.fat, perServing?.fat, unit: "g", showServing: serving != nil)
                row("  Saturated", per100.saturatedFat, perServing?.saturatedFat, unit: "g", showServing: serving != nil)
                row("Carbs", per100.carbs, perServing?.carbs, unit: "g", showServing: serving != nil)
                row("  Sugars", per100.sugars, perServing?.sugars, unit: "g", showServing: serving != nil)
                row("Fiber", per100.fiber, perServing?.fiber, unit: "g", showServing: serving != nil)
                row("Protein", per100.protein, perServing?.protein, unit: "g", showServing: serving != nil)
                row("Salt", per100.salt, perServing?.salt, unit: "g", showServing: serving != nil)
            }
            if let reason = product.implausibilityReason {
                Text(reason + " Check the label and fix it if it's wrong.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoAmber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
    }

    private func row(_ label: String, _ per100: Double?, _ portion: Double?, unit: String, showServing: Bool) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(Color.tempoTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(FoodProductView.amount(per100, unit: unit))
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextPrimary)
            if showServing {
                Text(FoodProductView.amount(portion, unit: unit))
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .font(.tempoBody)
    }

    private var missingCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("No label data yet")
                .font(.tempoBodyBold)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("We don't have the nutrition table for this product. Photograph its label and Tempo reads it for you.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
    }

    private func textCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(title)
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            Text(body)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard()
    }

    private var actions: some View {
        VStack(spacing: TempoSpacing.buttonStackVertical) {
            if hasLabel {
                Button("Label looks wrong? Photograph it") { showEditor = true }
                    .buttonStyle(.tempoSecondary)
                    .accessibilityIdentifier("labelPhotograph")
            } else {
                Button("Photograph the label") { showEditor = true }
                    .buttonStyle(.tempoPrimary)
                    .accessibilityIdentifier("labelPhotograph")
            }
            Button("Scan another", action: onScanAnother)
                .buttonStyle(.tempoGhost)
                .accessibilityIdentifier("labelScanAnother")
        }
    }
}
