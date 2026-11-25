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
    @Environment(\.tideMood)
    private var mood

    @State private var quantityText: String
    @State private var unit: PantryUnit
    @State private var storageLocation: PantryStorageLocation
    @State private var useBy: Date
    @State private var hasUseBy: Bool
    @State private var brand: String

    init(item: PantryItem, viewModel: NutritionTabViewModel) {
        self.item = item
        self.viewModel = viewModel
        _quantityText = State(initialValue: PantryQuantityFormatter.editText(item.quantity))
        _unit = State(initialValue: item.unit)
        _storageLocation = State(initialValue: item.storageLocation)
        _useBy = State(initialValue: item.useBy ?? Date())
        _hasUseBy = State(initialValue: item.useBy != nil)
        _brand = State(initialValue: item.brand)
    }

    var body: some View {
        NavigationStack {
            KitchenForm {
                Section {
                    header
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                KitchenFormSection(String(localized: "Item")) {
                    LabeledContent("Name", value: item.displayName)
                    TextField("Brand (optional)", text: $brand)
                        .textInputAutocapitalization(.words)
                }

                KitchenFormSection(String(localized: "Quantity")) {
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

                KitchenFormSection(String(localized: "Storage")) {
                    Picker("Location", selection: $storageLocation) {
                        ForEach(PantryStorageLocation.allCases, id: \.self) { loc in
                            Text(loc.displayName).tag(loc)
                        }
                    }
                    .pickerStyle(.segmented)
                    if storageLocation != item.storageLocation {
                        Text("Moving locations recomputes the use-by date, unless you set one below.")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                }

                KitchenFormSection(String(localized: "Use by")) {
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
        .kitchenSheet()
    }

    /// What is being edited, at a glance: the item, how much is left, and how soon it must be used.
    private var header: some View {
        HStack(spacing: Tide.s4) {
            Image(systemName: Self.icon(for: item.storageLocation))
                .font(Tide.title2)
                .foregroundStyle(mood.accent)
                .frame(width: Tide.Kitchen.heroDisc - Tide.s8, height: Tide.Kitchen.heroDisc - Tide.s8)
                .glassEffect(.regular.tint(Tide.glassCard), in: .rect(cornerRadius: Tide.tileRadius))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(item.displayName)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                TideNumber(
                    PantryQuantityFormatter.displayNumber(item.quantity),
                    unit: item.unit.displayName,
                    size: Tide.numeralM,
                    relativeTo: .title
                )
                if let days = item.daysUntilUseBy {
                    KitchenTag(
                        text: days < 0 ? String(localized: "Past use-by") : (days == 0 ? String(localized: "Use today") : String(localized: "\(days) days left")),
                        tint: days <= 1 ? Tide.danger : (days <= 3 ? Tide.Kitchen.warn : Tide.text2)
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tide.s1)
        .padding(.vertical, Tide.s2)
        .accessibilityElement(children: .combine)
    }

    private static func icon(for location: PantryStorageLocation) -> String {
        switch location {
        case .fridge: "thermometer.snowflake"
        case .freezer: "snowflake"
        case .pantry,
             .cupboard: "archivebox"
        }
    }

    private func save() {
        // Only rewrite the quantity if the user edited the text; otherwise
        // keep the exact stored value (0.8333 must not become 0.83 just
        // because the sheet was opened to change the location).
        let initialText = PantryQuantityFormatter.editText(item.quantity)
        let quantity = quantityText == initialText
            ? item.quantity
            : (Double(quantityText.replacingOccurrences(of: ",", with: ".")) ?? item.quantity)
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
