//
// GroceryDoneShoppingView.swift
// Tempo
//
// "Done shopping" review sheet (BUILD item 3): ticks on the grocery list are
// just ticks — this is where checked items actually become pantry stock.
// Lists every checked-but-not-yet-bought item with an editable amount/unit,
// an optional price paid, and a storage location (pre-guessed by category).
// "Add to pantry" routes each row through the existing pantry service so
// Lane B's expiry estimation on the add path runs exactly as it would for
// any other pantry add.
//

import SwiftUI

struct GroceryDoneShoppingView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    let list: GroceryList

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    private struct Row: Identifiable {
        let item: GroceryListItem
        var quantityText: String
        var unit: PantryUnit
        var storageLocation: PantryStorageLocation
        var priceText: String
        var include: Bool = true

        var id: UUID {
            item.id
        }
    }

    @State
    private var rows: [Row] = []

    private var includedCount: Int {
        rows.filter(\.include).count
    }

    var body: some View {
        NavigationStack {
            KitchenForm {
                if rows.isEmpty {
                    Section {
                        KitchenEmpty(
                            systemImage: "cart",
                            title: "Nothing checked off yet",
                            message: "Tick items on the list or in Store Mode first."
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        header
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    ForEach($rows) { $row in
                        rowSection(row: $row)
                    }
                }
            }
            .navigationTitle("Done Shopping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .kitchenBottomBar {
                Button {
                    confirm()
                } label: {
                    Label("Add to Pantry", systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(.tidePrimary)
                .disabled(rows.allSatisfy { !$0.include })
            }
        }
        .kitchenSheet()
        .onAppear(perform: loadRows)
    }

    /// The trip, turned into stock: how many of the ticked items are going in.
    private var header: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Into your pantry", trailing: includedCount == rows.count ? "All of it" : "\(rows.count - includedCount) left out")
            TideNumber("\(includedCount)", unit: includedCount == 1 ? "item" : "items", size: Tide.numeralL, relativeTo: .largeTitle)
            TideLevelBar(
                progress: Double(includedCount) / Double(max(rows.count, 1)),
                color: mood.accent,
                height: Tide.bar
            )
            .animation(Tide.settle, value: includedCount)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
        .accessibilityElement(children: .combine)
    }

    private func loadRows() {
        rows = list.activeItems
            .filter { $0.isChecked && !$0.isBought }
            .map { item in
                Row(
                    item: item,
                    quantityText: formatQuantity(item.quantity),
                    unit: item.unit,
                    storageLocation: GroceryStoreLayout.guessedStorageLocation(forCategory: item.category),
                    priceText: ""
                )
            }
    }

    private func rowSection(row: Binding<Row>) -> some View {
        Section {
            Toggle(row.wrappedValue.item.displayName, isOn: row.include)
                .font(Tide.headline)
            if row.wrappedValue.include {
                HStack {
                    TextField("Amount", text: row.quantityText)
                        // Packs/cans are tracked in fractions ("0.5 pack"), so
                        // countable units need the decimal pad too.
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: row.unit) {
                        ForEach(PantryUnit.allCases, id: \.self) { u in
                            Text(u.displayName).tag(u)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Picker("Storage", selection: row.storageLocation) {
                    ForEach(PantryStorageLocation.allCases, id: \.self) { loc in
                        Label(loc.displayName, systemImage: loc.icon).tag(loc)
                    }
                }
                HStack {
                    Text("Paid (optional)")
                    Spacer()
                    Text("$")
                        .foregroundStyle(Tide.text2)
                    TextField("0.00", text: row.priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: Tide.Kitchen.row + Tide.s6)
                }
            }
        }
    }

    private func confirm() {
        let confirmations: [NutritionTabViewModel.GroceryBoughtConfirmation] = rows
            .filter(\.include)
            .compactMap { row in
                // The pantry tracks part-used containers ("0.5 pack"), so
                // keep what the user typed. List amounts are already whole.
                let typed = Double(row.quantityText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? row.item.quantity
                let quantity = max(0, typed)
                guard quantity > 0, quantity.isFinite else {
                    return nil
                }
                let price = Double(row.priceText.replacingOccurrences(of: ",", with: "."))
                return .init(
                    item: row.item,
                    quantity: quantity,
                    unit: row.unit,
                    storageLocation: row.storageLocation,
                    totalPaidUSD: (price ?? 0) > 0 ? price : nil
                )
            }
        viewModel.confirmGroceryBought(confirmations)
        HapticManager.notification(.success)
        dismiss()
    }

    private func formatQuantity(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
