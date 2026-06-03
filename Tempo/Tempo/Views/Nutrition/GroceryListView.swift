//
// GroceryListView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftData
import SwiftUI

struct GroceryListView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    /// True while the AddGroceryItemSheet is presented.
    @State
    private var showAddItem = false

    /// Inline result message after a pantry-sync run ("removed 3 items").
    @State
    private var pantrySyncMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                headerCard
                if let list = viewModel.groceryState.latest {
                    progressBar(for: list)
                    ForEach(groupedCategories(for: list), id: \.self) { category in
                        categorySection(category: category, items: items(in: list, category: category))
                    }
                    exportButton(for: list)
                } else {
                    emptyState
                }
                if let error = viewModel.groceryState.lastError {
                    Text(error)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.lg)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Grocery List")
        .toolbar {
            // Only surface Add/Sync when a list actually exists — there's
            // nothing to add to or sync against until generation runs.
            if viewModel.groceryState.latest != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddItem = true
                        } label: {
                            Label("Add Item", systemImage: "plus")
                        }
                        Button {
                            let removed = viewModel.reapplyPantryToGrocery()
                            pantrySyncMessage = removed == 0
                                ? "List is already in sync with pantry"
                                : "Removed \(removed) item\(removed == 1 ? "" : "s") already in pantry"
                            HapticManager.lightImpact()
                        } label: {
                            Label("Sync with Pantry", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddGroceryItemSheet { name, qty, unit in
                viewModel.addGroceryItem(name: name, quantity: qty, unit: unit)
            }
        }
        .alert("Pantry Sync", isPresented: Binding(
            get: { pantrySyncMessage != nil },
            set: { if !$0 { pantrySyncMessage = nil } }
        )) {
            Button("OK") { pantrySyncMessage = nil }
        } message: {
            Text(pantrySyncMessage ?? "")
        }
        .task {
            viewModel.attachPhase7Services(modelContext: modelContext, services: services)
            viewModel.reloadGrocery()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(alignment: .center, spacing: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("THIS WEEK")
                    .font(.tempoModuleTag)
                    .foregroundStyle(Color.tempoTextTertiary)
                if let list = viewModel.groceryState.latest {
                    Text("\(list.itemCount) items, \(list.checkedCount) checked")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                } else {
                    Text("No list generated yet")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            Spacer()
            Button {
                viewModel.generateGroceryList()
            } label: {
                if viewModel.groceryState.isGenerating {
                    ProgressView().tint(.white)
                } else {
                    Label("Generate", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.tempoPrimary)
            .disabled(viewModel.groceryState.isGenerating)
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func progressBar(for list: GroceryList) -> some View {
        let total = max(1, list.itemCount)
        let progress = Double(list.checkedCount) / Double(total)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.tempoBorder.opacity(0.5)).frame(height: 6)
                    Capsule().fill(Color.tempoSignal).frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
            Text("\(Int(progress * 100))% checked off")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    // MARK: - Per-category section

    private func groupedCategories(for list: GroceryList) -> [String] {
        // Store-aisle order rather than alphabetical: produce first (you
        // shop the perimeter), dairy / protein next, then dry goods, with
        // unknown categories falling to the end. Without this the list was
        // pantry → grains → produce, which is the reverse of how anyone
        // actually moves through a grocery store.
        // "protein" kept for older lists; new lists split meat/seafood out.
        let preferred = ["produce", "meat", "seafood", "protein", "dairy", "frozen", "grains", "oils", "pantry"]
        let present = Array(Set(list.orderedItems.map(\.category)))
        let known = preferred.filter { present.contains($0) }
        let unknown = present.filter { !preferred.contains($0) }.sorted()
        return known + unknown
    }

    private func items(in list: GroceryList, category: String) -> [GroceryListItem] {
        list.orderedItems.filter { $0.category == category }
    }

    private func categorySection(category: String, items: [GroceryListItem]) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(category.uppercased())
                .font(.tempoModuleTag)
                .foregroundStyle(Color.tempoTextSecondary)
            ForEach(items, id: \.id) { item in
                Button {
                    viewModel.toggleGroceryItem(item)
                } label: {
                    HStack(spacing: TempoSpacing.sm) {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isChecked ? Color.tempoSuccess : Color.tempoTextTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                                .strikethrough(item.isChecked)
                            Text("\(formatQuantity(item.quantity))\(item.unit.displayName)")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                // Long-press to delete. Can't use SwiftUI swipeActions here
                // because the list isn't inside a List/Form — these rows
                // are a custom VStack. The contextMenu works on any tap
                // target and matches iOS's expected long-press affordance.
                .contextMenu {
                    Button(role: .destructive) {
                        viewModel.deleteGroceryItem(item)
                        HapticManager.notification(.warning)
                    } label: {
                        Label("Remove from List", systemImage: "trash")
                    }
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Reminders export

    private func exportButton(for list: GroceryList) -> some View {
        Button {
            Task {
                await viewModel.exportGroceryListToReminders()
            }
        } label: {
            HStack {
                if viewModel.groceryState.isExporting {
                    ProgressView().tint(.white)
                }
                Label(
                    list.exportedToReminders ? "Re-export to Reminders" : "Export to Reminders",
                    systemImage: "list.bullet.rectangle.fill"
                )
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.tempoSecondary)
        .disabled(viewModel.groceryState.isExporting)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: "cart")
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoTextTertiary)
            Text("No grocery list yet")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Generate a meal plan first, then tap Generate to build your shopping list.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxxl)
    }

    private func formatQuantity(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

// MARK: - AddGroceryItemSheet

/// Modal for adding a one-off item to the current grocery list. Fires
/// `onAdd(name, quantity, unit)` on save and dismisses. Used when the user
/// needs something the auto-generated list didn't include ("oh, also: olive
/// oil"). Kept intentionally minimal — no category picker, no aisle tagging;
/// the VM defaults the category to "pantry" which falls to the end of the
/// store-aisle order.
private struct AddGroceryItemSheet: View {
    var onAdd: (String, Double, PantryUnit) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var name: String = ""
    @State
    private var quantityText: String = "1"
    @State
    private var unit: PantryUnit = .pieces

    private var parsedQuantity: Double {
        Double(quantityText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedQuantity > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name (e.g. olive oil)", text: $name)
                        .textInputAutocapitalization(.never)
                }
                Section("Quantity") {
                    HStack {
                        TextField("Amount", text: $quantityText)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $unit) {
                            ForEach(PantryUnit.allCases, id: \.self) { u in
                                Text(u.displayName).tag(u)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .navigationTitle("Add to Grocery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(name.trimmingCharacters(in: .whitespaces), parsedQuantity, unit)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
