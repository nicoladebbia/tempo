//
// GroceryListView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - GroceryListView

struct GroceryListView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.tideMood)
    private var mood

    /// True while the AddGroceryItemSheet is presented.
    @State
    private var showAddItem = false

    /// Inline result message after a pantry-sync run ("removed 3 items").
    @State
    private var pantrySyncMessage: String?

    /// Full-screen Store Mode presentation.
    @State
    private var showStoreMode = false

    /// "Done shopping" bought → pantry review sheet.
    @State
    private var showDoneShopping = false

    /// Weekly spend vs. budget history.
    @State
    private var showSpendHistory = false

    /// Cheaper-swaps suggestion sheet (over-budget path).
    @State
    private var showCheaperSwaps = false

    @State
    private var ticks = 0

    /// Something is presented over the page: its shaders stop.
    private var isCovered: Bool {
        showAddItem || showStoreMode || showDoneShopping || showSpendHistory || showCheaperSwaps
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s5) {
                if let list = viewModel.groceryState.latest {
                    summaryCard(for: list)
                    ForEach(viewModel.resolvedGroceryCategoryOrder(for: list), id: \.self) { category in
                        categorySection(category: category, items: items(in: list, category: category))
                    }
                    if !list.boughtItems.isEmpty {
                        boughtSection(for: list)
                    }
                    exportButton(for: list)
                } else {
                    emptyState
                }
                if let error = viewModel.groceryState.lastError {
                    Text(error)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .tidePage()
        .tideCovered(isCovered)
        .sensoryFeedback(.selection, trigger: ticks)
        .toolbar {
            // Only surface Add/Sync when a list actually exists — there's
            // nothing to add to or sync against until generation runs.
            if let list = viewModel.groceryState.latest {
                // feat/grocery-share-order (Lane C) — share as text / live link / order online.
                ToolbarItem(placement: .topBarTrailing) {
                    GroceryShareMenu(list: list)
                }
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
                        Button {
                            showSpendHistory = true
                        } label: {
                            Label("Spend History", systemImage: "chart.bar.fill")
                        }
                        storePickerMenu
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddGroceryItemSheet { name, qty, unit in
                viewModel.addGroceryItem(name: name, quantity: qty, unit: unit)
            }
        }
        .sheet(isPresented: $showDoneShopping) {
            if let list = viewModel.groceryState.latest {
                GroceryDoneShoppingView(viewModel: viewModel, list: list)
            }
        }
        .sheet(isPresented: $showSpendHistory) {
            GroceryWeeklySpendView(viewModel: viewModel)
        }
        .sheet(isPresented: $showCheaperSwaps) {
            CheaperSwapsSheet(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showStoreMode) {
            if let list = viewModel.groceryState.latest {
                GroceryStoreModeView(viewModel: viewModel, list: list) {
                    showStoreMode = false
                    showDoneShopping = true
                }
            }
        }
        .alert("Pantry Sync", isPresented: Binding(
            get: { pantrySyncMessage != nil },
            set: {
                if !$0 {
                    pantrySyncMessage = nil
                }
            }
        )) {
            Button("OK") { pantrySyncMessage = nil }
        } message: {
            Text(pantrySyncMessage ?? "")
        }
        .task {
            viewModel.attachPhase7Services(modelContext: modelContext, services: services)
            viewModel.reloadGrocery()
            viewModel.refreshGroceryPrices()
        }
    }

    // MARK: - Store picker

    private var storePickerMenu: some View {
        Menu {
            ForEach(GroceryStore.allCases) { store in
                Button {
                    viewModel.groceryActiveStore = store
                } label: {
                    if viewModel.groceryActiveStore == store {
                        Label(store.displayName, systemImage: "checkmark")
                    } else {
                        Text(store.displayName)
                    }
                }
            }
        } label: {
            Label("Store: \(viewModel.groceryActiveStore.displayName)", systemImage: "cart.fill")
        }
    }

    // MARK: - Summary: progress, cost, the way into Store Mode

    private func summaryCard(for list: GroceryList) -> some View {
        let total = max(1, list.itemCount)
        let progress = Double(list.checkedCount) / Double(total)
        return VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "This week", trailing: progress >= 1 ? "All checked" : nil)
            TideNumber(
                "\(list.checkedCount)", unit: "of \(list.itemCount) checked",
                size: Tide.numeralL, relativeTo: .largeTitle
            )
            TideLevelBar(progress: progress, color: mood.accent, height: Tide.bar)
                .animation(Tide.settle, value: progress)
                .accessibilityLabel("Checked off")
            budgetLine(for: list)
            HStack(spacing: Tide.s3) {
                Button {
                    showStoreMode = true
                } label: {
                    Label("Store Mode", systemImage: "figure.walk")
                }
                .buttonStyle(.tidePrimary)
                .sensoryFeedback(.impact(weight: .light), trigger: showStoreMode)
                Button {
                    viewModel.generateGroceryList()
                } label: {
                    if viewModel.groceryState.isGenerating {
                        ProgressView()
                            .frame(minHeight: Tide.hit + Tide.s2)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .frame(minHeight: Tide.hit + Tide.s2)
                    }
                }
                .buttonStyle(.tideGlass)
                .fixedSize()
                .disabled(viewModel.groceryState.isGenerating)
                .accessibilityLabel("Generate list")
            }
        }
        .tideCard()
    }

    private func budgetLine(for list: GroceryList) -> some View {
        let cap = viewModel.groceryBudgetCapUSD
        let total = list.estimatedTotalUSD
        let isOver = viewModel.groceryIsOverBudget()
        return VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber(
                    list.totalIsApproximate ? "≈ \(formatUSD(total))" : formatUSD(total),
                    size: Tide.numeralS, relativeTo: .headline,
                    color: isOver ? Tide.danger : Tide.text
                )
                if list.hasUnresolvedPrices {
                    Text("pricing…")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
                Spacer(minLength: Tide.s2)
                if let cap {
                    Text("of $\(cap) budget")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
            if isOver {
                HStack(spacing: Tide.s3) {
                    Text("Over budget. Tighten up or swap something.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Tide.s2)
                    TideChip(title: "Cheaper swaps") {
                        showCheaperSwaps = true
                        Task { await viewModel.fetchCheaperSwaps() }
                    }
                }
            }
        }
    }

    private func formatUSD(_ value: Double) -> String {
        "$" + String(format: "%.2f", value)
    }

    // MARK: - Bought section (Done-shopping record)

    private func boughtSection(for list: GroceryList) -> some View {
        KitchenGroup(
            title: "Bought",
            systemImage: "checkmark.circle.fill",
            trailing: "\(list.boughtItems.count)",
            tint: Tide.Kitchen.good
        ) {
            ForEach(list.boughtItems, id: \.id) { item in
                HStack(spacing: Tide.s3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.Kitchen.good)
                        .accessibilityHidden(true)
                    Text(item.displayName)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .strikethrough()
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Per-category section

    private func items(in list: GroceryList, category: String) -> [GroceryListItem] {
        list.activeItems.filter { $0.category == category }
    }

    private func categorySection(category: String, items: [GroceryListItem]) -> some View {
        let left = items.filter { !$0.isChecked }.count
        return KitchenGroup(
            title: category,
            trailing: left == 0 ? "Done" : "\(left) left"
        ) {
            ForEach(items, id: \.id) { item in
                Button {
                    viewModel.toggleGroceryItem(item)
                    ticks += 1
                    if item.isChecked {
                        viewModel.recordGroceryCategoryTick(item.category)
                    }
                } label: {
                    itemRow(item)
                }
                .buttonStyle(.plain)
                .accessibilityValue(item.isChecked ? "Checked" : "Not checked")
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
    }

    private func itemRow(_ item: GroceryListItem) -> some View {
        HStack(spacing: Tide.s3) {
            KitchenCheck(checked: item.isChecked)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(item.displayName)
                    .font(Tide.headline)
                    .foregroundStyle(item.isChecked ? Tide.text3 : Tide.text)
                    .strikethrough(item.isChecked)
                    .fixedSize(horizontal: false, vertical: true)
                // "4 breasts chicken" already carries its amount.
                if !item.displayNameEmbedsQuantity {
                    Text("\(formatQuantity(item.quantity))\(item.unit.displayName)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
            Spacer(minLength: Tide.s2)
            if let price = item.estimatedPriceUSD {
                Text(item.priceSource == .estimate ? "≈\(formatUSD(price))" : formatUSD(price))
                    .font(Tide.numeral(Tide.numeralS, .semibold))
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
        }
        .contentShape(.rect)
    }

    // MARK: - Reminders export

    private func exportButton(for list: GroceryList) -> some View {
        Button {
            Task {
                await viewModel.exportGroceryListToReminders()
            }
        } label: {
            HStack(spacing: Tide.s2) {
                if viewModel.groceryState.isExporting {
                    ProgressView()
                }
                Label(
                    list.exportedToReminders ? "Re-export to Reminders" : "Export to Reminders",
                    systemImage: "list.bullet.rectangle.fill"
                )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tideGlass)
        .disabled(viewModel.groceryState.isExporting)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Tide.s3) {
            Image(systemName: "cart")
                .font(Tide.largeTitle)
                .foregroundStyle(mood.accent)
                .accessibilityHidden(true)
            Text("No grocery list yet")
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
            Text("Generate a meal plan first, then tap Generate to build your shopping list.")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                viewModel.generateGroceryList()
            } label: {
                if viewModel.groceryState.isGenerating {
                    ProgressView()
                } else {
                    Label("Generate", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.tidePrimary)
            .disabled(viewModel.groceryState.isGenerating)
            .padding(.top, Tide.s2)
        }
        .frame(maxWidth: .infinity)
        .tideCard(padding: Tide.s6)
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
            KitchenForm {
                KitchenFormSection("Item") {
                    TextField("Name (e.g. olive oil)", text: $name)
                        .textInputAutocapitalization(.never)
                }
                KitchenFormSection("Quantity") {
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
        .kitchenSheet()
    }
}
