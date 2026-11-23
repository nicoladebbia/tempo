//
// KitchenView.swift
// Tempo
//
// One home for everything you own or buy: Pantry (default), Groceries,
// Receipts and Supplements. A glass segmented control on top switches
// between them.
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
            ) { $0.rawValue }
                .padding(.horizontal, Tide.edge)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Kitchen section")
                .accessibilityIdentifier("kitchenSectionPicker")

            switch viewModel.selectedKitchen {
            case .pantry:
                PantryView(viewModel: viewModel)
            case .groceries:
                GroceryListView(viewModel: viewModel)
            case .receipts:
                ReceiptsHistoryView(viewModel: viewModel)
            case .supplements:
                SupplementsView(openSupplementID: $viewModel.supplementToOpen)
            }
        }
        // Fuel's page already draws the field behind the four sections, so
        // they must not each draw a second one.
        .environment(\.tideInsidePage, true)
    }
}
