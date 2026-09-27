//
// PantryItemEditSheet.swift
// Tempo
//
// Tap-to-edit for a single pantry row — quantity, unit, storage location,
// use-by date, brand. Routes through NutritionTabViewModel.updatePantryItem
// (→ PantryServiceProtocol.updateItem), the same path the voice-edit flow
// uses, so both surfaces stay in sync with the location-change→recompute
// rule.
//

import SwiftUI

struct PantryItemEditSheet: View {
    let item: PantryItem
    @Bindable
    var viewModel: NutritionTabViewModel

    @Environment(\.dismiss)
    private var dismiss

    @State private var quantityText: String
    @State private var unit: PantryUnit
    @State private var storageLocation: PantryStorageLocation
    @State private var useBy: Date
    @State private var hasUseBy: Bool
    @State private var brand: String

    init(item: PantryItem, viewModel: NutritionTabViewModel) {
        self.item = item
        self.viewModel = viewModel
        _quantityText = State(initialValue: item.quantity == item.quantity.rounded() ? "\(Int(item.quantity))" : String(
            format: "%.1f",
            item.quantity
        ))
        _unit = State(initialValue: item.unit)
        _storageLocation = State(initialValue: item.storageLocation)
        _useBy = State(initialValue: item.useBy ?? Date())
        _hasUseBy = State(initialValue: item.useBy != nil)
        _brand = State(initialValue: item.brand)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    LabeledContent("Name", value: item.displayName)
                    TextField("Brand (optional)", text: $brand)
                        .textInputAutocapitalization(.words)
                }

                Section("Quantity") {
                    HStack {
                        TextField("Quantity", text: $quantityText)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $unit) {
                            ForEach(PantryUnit.allCases, id: \.self) { u in
                                Text(u.displayName).tag(u)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Storage") {
                    Picker("Location", selection: $storageLocation) {
                        ForEach(PantryStorageLocation.allCases, id: \.self) { loc in
                            Text(loc.displayName).tag(loc)
                        }
                    }
                    .pickerStyle(.segmented)
                    if storageLocation != item.storageLocation {
                        Text("Moving locations recomputes the use-by date, unless you set one below.")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }

                Section("Use by") {
                    Toggle("Track a use-by date", isOn: $hasUseBy)
                    if hasUseBy {
                        DatePicker("Use by", selection: $useBy, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let quantity = Double(quantityText.replacingOccurrences(of: ",", with: ".")) ?? item.quantity
        // `nil` means "leave useBy alone" to `updateItem` — UNLESS storage
        // location also changed, in which case it recomputes from the new
        // location (same rule the voice-edit "move" intent uses). Passing
        // the explicit date here when the toggle is on always wins over
        // that recompute.
        let explicitUseBy: Date? = hasUseBy ? useBy : nil
        viewModel.updatePantryItem(
            item,
            quantity: quantity,
            unit: unit,
            storageLocation: storageLocation,
            useBy: explicitUseBy,
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        dismiss()
    }
}
