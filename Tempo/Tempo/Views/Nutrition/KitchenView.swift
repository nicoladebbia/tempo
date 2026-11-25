//
// KitchenView.swift
// Tempo
//
// One home for everything you own or buy: Pantry (default), Groceries,
// Spending (receipts and what the shop cost) and Supplements. A glass
// segmented control on top switches between them.
//

import SwiftUI

struct KitchenView: View {
    @Bindable
    var viewModel: NutritionTabViewModel

    var body: some View {
        VStack(spacing: Tide.s2) {
            KitchenSegmented(
                options: Array(KitchenSection.allCases),
                selection: $viewModel.selectedKitchen
            ) { $0 == .receipts ? String(localized: "Spending") : $0.displayName }
                .padding(.horizontal, Tide.edge)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Kitchen section")
                .accessibilityIdentifier("kitchenSectionPicker")

            // Each section fades in as the segmented control's pill lands on it.
            Group {
                switch viewModel.selectedKitchen {
                case .pantry:
                    PantryView(viewModel: viewModel)
                        .firstTip("fuel.pantry", "Scan a receipt and Tempo tells you what to use up first.")
                case .groceries:
                    GroceryListView(viewModel: viewModel)
                        .firstTip("fuel.groceries", "Tick items off as you shop, or open Store Mode.")
                case .receipts:
                    SpendingView(viewModel: viewModel)
                        .firstTip("fuel.spending", "Scan every receipt so this week's total is the real one.")
                case .supplements:
                    SupplementsView(openSupplementID: $viewModel.supplementToOpen)
                        .firstTip("fuel.supplements", "Tick a supplement when you take it, and Tempo counts the days left.")
                }
            }
            .transition(.opacity)
        }
        .animation(Tide.snap, value: viewModel.selectedKitchen)
        // Fuel's page already draws the field behind the four sections, so
        // they must not each draw a second one.
        .environment(\.tideInsidePage, true)
    }
}
