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
        #if DEBUG
            .modifier(Rework3DebugRoute(viewModel: viewModel))
        #endif
    }
}

#if DEBUG
    // REWORK3-DEBUG: temporary QA route, removed before the final commit.
    import SwiftData
    import UIKit

    private struct Rework3DebugRoute: ViewModifier {
        @Bindable
        var viewModel: NutritionTabViewModel
        @Environment(ServiceContainer.self)
        private var services
        @State
        private var shown: String?

        private static let name: String? = ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--rework3-debug=") }
            .map { String($0.dropFirst("--rework3-debug=".count)) }

        func body(content: Content) -> some View {
            content
                .onAppear {
                    if shown == nil, let name = Self.name {
                        shown = name
                    }
                }
                .fullScreenCover(item: Binding(get: { shown.map(DebugName.init) }, set: { shown = $0?.value })) { item in
                    debugView(item.value)
                }
        }

        struct DebugName: Identifiable {
            let value: String
            var id: String { value }
        }

        private static func sampleImage() -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 300, height: 380)).image { ctx in
                UIColor(white: 0.93, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 380))
                UIColor.darkGray.setFill()
                for row in 0 ..< 18 {
                    ctx.fill(CGRect(x: 24, y: 30 + row * 18, width: row % 3 == 0 ? 180 : 230, height: 6))
                }
            }
        }

        @ViewBuilder
        private func debugView(_ name: String) -> some View {
            switch name {
            case "receipt-processing", "receipt-processing-early":
                let progress = ReceiptScanProgress()
                let _ = name == "receipt-processing" ? {
                    progress.parsed(store: "Publix", total: 61.37, itemCount: 13)
                    progress.advance(to: .matchingProducts)
                }() : ()
                ReceiptProcessingView(images: [Self.sampleImage()], progress: progress)
                    .kitchenPage()
            case "picker":
                ReceiptProductPickerView(
                    line: ReceiptLineItem(rawText: "NUTELLA 13OZ", canonicalFoodName: "hazelnut spread", displayName: "Hazelnut spread", quantity: 1, unit: .each, totalPrice: 4.49),
                    storeChain: "publix"
                ) { _, _ in }
            case "usesoon":
                ScrollView {
                    UseUpSoonCard(viewModel: viewModel)
                        .padding(Tide.edge)
                }
                .tidePage()
                .onAppear {
                    let recipe = Recipe(name: "Lemon chicken bowl")
                    let other = Recipe(name: "Garlic broccoli rice")
                    viewModel.recipeState.suggestions = [
                        RecipeSuggestion(recipe: recipe, presentIngredients: ["chicken breast", "broccoli"], missingIngredients: [], coverageScore: 0.9, macroAlignmentScore: 0.8, expiryUrgencyScore: 0.9),
                        RecipeSuggestion(recipe: other, presentIngredients: ["broccoli", "rice"], missingIngredients: ["garlic"], coverageScore: 0.7, macroAlignmentScore: 0.7, expiryUrgencyScore: 0.4),
                    ]
                }
            case "label-missing":
                NavigationStack {
                    ScannedProductLabelView(
                        product: FoodProduct(id: "dbg", name: "Mystery granola", source: .userAdded, per100g: .init()),
                        catalog: FoodCatalog(services: services),
                        onUpdated: { _ in },
                        onScanAnother: {}
                    )
                }
            default:
                Text("unknown debug route \(name)")
            }
        }
    }
#endif
