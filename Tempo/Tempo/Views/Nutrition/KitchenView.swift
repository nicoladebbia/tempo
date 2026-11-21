//
// KitchenView.swift
// Tempo
//
// One home for everything you own or buy: Pantry (default), Groceries,
// Receipts and Supplements. A small sub-picker on top switches between them.
//

import SwiftUI

struct KitchenView: View {
    @Bindable
    var viewModel: NutritionTabViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Kitchen section", selection: $viewModel.selectedKitchen) {
                ForEach(KitchenSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.sm)
            .accessibilityIdentifier("kitchenSectionPicker")
            .onChange(of: viewModel.selectedKitchen) { _, _ in
                HapticManager.selection()
            }

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
    }
}
