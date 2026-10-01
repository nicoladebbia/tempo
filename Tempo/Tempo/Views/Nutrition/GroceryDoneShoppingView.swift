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

    var body: some View {
        NavigationStack {
            Form {
                if rows.isEmpty {
                    Section {
                        Text("Nothing checked off yet — tick items on the list or in Store Mode first.")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                } else {
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Pantry") {
                        confirm()
                    }
                    .disabled(rows.allSatisfy { !$0.include })
                }
            }
        }
        .onAppear(perform: loadRows)
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
                .font(.tempoBodyBold)
            if row.wrappedValue.include {
                HStack {
                    TextField("Amount", text: row.quantityText)
                        .keyboardType(row.wrappedValue.unit.isCountable ? .numberPad : .decimalPad)
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
                        .foregroundStyle(Color.tempoTextSecondary)
                    TextField("0.00", text: row.priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
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
                let typed = Double(row.quantityText.replacingOccurrences(of: ",", with: ".")) ?? row.item.quantity
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
