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

            // Each section fades in as the segmented control's pill lands on it.
            Group {
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
            .transition(.opacity)
        }
        .animation(Tide.snap, value: viewModel.selectedKitchen)
        // Fuel's page already draws the field behind the four sections, so
        // they must not each draw a second one.
        .environment(\.tideInsidePage, true)
    }
}
