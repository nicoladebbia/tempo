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
    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// True while the AddGroceryItemSheet is presented.
    @State
    private var showAddItem = false

    /// The Undo toast for a tick, an add or a remove. It takes its own room above the Store Mode
    /// bar: the Fuel host's toast floats over the rows and that bar, and a tap on its Undo can
    /// reach them instead.
    @State
    private var toast: ToastData?

    /// Inline result message after a pantry-sync run ("removed 3 items").
    @State
    private var pantrySyncMessage: String?

    /// Full-screen Store Mode presentation.
    @State
    private var showStoreMode = false

    /// "Done shopping" bought → pantry review sheet.
    @State
    private var showDoneShopping = false

    /// Cheaper-swaps suggestion sheet (over-budget path).
    @State
    private var showCheaperSwaps = false

    @State
    private var ticks = 0
    @Namespace
    private var zoom

    /// Something is presented over the page: its shaders stop.
    private var isCovered: Bool {
        showAddItem || showStoreMode || showDoneShopping || showCheaperSwaps
    }

    var body: some View {
        Group {
            if let list = viewModel.groceryState.latest {
                listPage(list)
            } else {
                emptyState
            }
        }
        .tidePage()
        .tideCovered(isCovered)
        .sensoryFeedback(.selection, trigger: ticks)
        .sheet(isPresented: $showAddItem) {
            AddGroceryItemSheet { name, qty, unit in
                viewModel.addGroceryItemWithUndo(name: name, quantity: qty, unit: unit) { toast = $0 }
            }
        }
        .sheet(isPresented: $showDoneShopping) {
            if let list = viewModel.groceryState.latest {
                GroceryDoneShoppingView(viewModel: viewModel, list: list)
            }
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
                .navigationTransition(.zoom(sourceID: "storeMode", in: zoom))
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

    // MARK: - The list

    private func listPage(_ list: GroceryList) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s5) {
                summaryCard(for: list)
                ForEach(viewModel.resolvedGroceryCategoryOrder(for: list), id: \.self) { category in
                    categorySection(category: category, items: items(in: list, category: category))
                }
                if !list.boughtItems.isEmpty {
                    boughtSection(for: list)
                }
                addItemRow
                exportButton(for: list)
                if let error = viewModel.groceryState.lastError {
                    KitchenNotice(systemImage: "exclamationmark.triangle.fill", text: error, tint: Tide.danger)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s4)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        // Before the bottom bar, so the toast rests above "Store Mode", not on it.
        .kitchenToast($toast)
        // The way into the shop sits where the thumb is, not up in the card.
        .kitchenBottomBar {
            Button {
                showStoreMode = true
            } label: {
                Label("Store Mode", systemImage: "figure.walk")
            }
            .buttonStyle(.kitchenBar)
            .matchedTransitionSource(id: "storeMode", in: zoom)
            .sensoryFeedback(.impact(weight: .light), trigger: showStoreMode)
        }
    }

    /// Everything that used to live in the navigation bar, which the Fuel tab
    /// hides: add, rebuild, sync with the pantry, spend history, the store.
    private var moreMenu: some View {
        Menu {
            Button {
                showAddItem = true
            } label: {
                Label("Add Item", systemImage: "plus")
            }
            Button {
                viewModel.generateGroceryList()
            } label: {
                Label("Generate list", systemImage: "wand.and.stars")
            }
            .disabled(viewModel.groceryState.isGenerating)
            Button {
                let removed = viewModel.reapplyPantryToGrocery()
                pantrySyncMessage = removed == 0
                    ? String(localized: "List is already in sync with pantry")
                    : String(localized: "Removed \(removed) items already in pantry")
                HapticManager.lightImpact()
            } label: {
                Label("Sync with Pantry", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                viewModel.openKitchen(.receipts)
            } label: {
                Label("Spending", systemImage: "chart.bar.fill")
            }
            storePickerMenu
        } label: {
            KitchenGlassIcon(systemImage: "ellipsis", isWorking: viewModel.groceryState.isGenerating)
        }
        .accessibilityLabel("More")
    }

    private var addItemRow: some View {
        Button {
            showAddItem = true
        } label: {
            Label("Add an item", systemImage: "plus")
                .font(Tide.bodyStrong)
                .foregroundStyle(mood.accent)
                .frame(maxWidth: .infinity, minHeight: Tide.hit)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
            HStack(spacing: Tide.s2) {
                Text("This week").tideLabel()
                if progress >= 1 {
                    KitchenTag(text: String(localized: "All checked"), tint: Tide.Kitchen.good)
                }
                Spacer(minLength: Tide.s2)
                GroceryShareMenu(list: list)
                moreMenu
            }
            TideNumber(
                "\(list.checkedCount)", unit: String(localized: "of \(list.itemCount) checked"),
                size: Tide.numeralL, relativeTo: .largeTitle,
                color: progress >= 1 ? Tide.Kitchen.good : Tide.text
            )
            TideLevelBar(progress: progress, color: progress >= 1 ? Tide.Kitchen.good : mood.accent, height: Tide.bar)
                .animation(Tide.settle, value: progress)
                .accessibilityLabel("Checked off")
            budgetLine(for: list)
        }
        .tideCard()
    }

    /// What the list costs against what you set aside: the total, and a bar
    /// that fills toward the budget and turns red when it passes it.
    private func budgetLine(for list: GroceryList) -> some View {
        let cap = viewModel.groceryBudgetCapUSD
        let total = list.estimatedTotalUSD
        let isOver = viewModel.groceryIsOverBudget()
        let spent = cap.map { $0 > 0 ? min(total / Double($0), 1) : 0 } ?? 0
        return VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    TideNumber(
                        list.totalIsApproximate ? "≈ \(formatUSD(total))" : formatUSD(total),
                        size: Tide.numeralM, relativeTo: .title,
                        color: isOver ? Tide.danger : Tide.text
                    )
                    if list.hasUnresolvedPrices {
                        Text("pricing…")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                }
                .explains(.fuelGroceryTotal.showing(formatUSD(total)))
                Spacer(minLength: Tide.s2)
                if let cap {
                    Text("of $\(cap) budget")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                        .explains(.fuelGroceryBudget.showing("$\(cap)"))
                }
            }
            if cap != nil {
                TideLevelBar(progress: spent, color: isOver ? Tide.danger : Tide.water, height: Tide.barSlim)
                    .animation(Tide.settle, value: spent)
                    .accessibilityLabel("Budget used")
            }
            if isOver {
                let stacked = typeSize.isAccessibilitySize
                let layout = stacked
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
                    : AnyLayout(HStackLayout(spacing: Tide.s3))
                layout {
                    Text("Over budget. Tighten up or swap something.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    if !stacked {
                        Spacer(minLength: Tide.s2)
                    }
                    TideChip(title: String(localized: "Cheaper swaps")) {
                        showCheaperSwaps = true
                        Task { await viewModel.fetchCheaperSwaps() }
                    }
                }
            }
        }
    }

    private func formatUSD(_ value: Double) -> String {
        "$" + value.tempoDecimal(2)
    }

    // MARK: - Bought section (Done-shopping record)

    private func boughtSection(for list: GroceryList) -> some View {
        KitchenGroup(
            title: String(localized: "Bought"),
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
            title: GroceryAisleName.display(category),
            trailing: left == 0 ? String(localized: "status.done", defaultValue: "Done", comment: "Status word: a step, task or workout is finished (not the Done button)") : String(localized: "\(left) left")
        ) {
            ForEach(items, id: \.id) { item in
                Button {
                    let undoToast = viewModel.toggleGroceryItemWithUndo(item)
                    ticks += 1
                    if item.isChecked {
                        viewModel.recordGroceryCategoryTick(item.category)
                    }
                    if let undoToast {
                        toast = undoToast
                    }
                } label: {
                    itemRow(item)
                }
                .buttonStyle(.plain)
                .accessibilityValue(item.isChecked ? String(localized: "Checked") : String(localized: "Not checked"))
                // Long-press to delete. Can't use SwiftUI swipeActions here
                // because the list isn't inside a List/Form — these rows
                // are a custom VStack. The contextMenu works on any tap
                // target and matches iOS's expected long-press affordance.
                .contextMenu {
                    Button(role: .destructive) {
                        viewModel.deleteGroceryItemWithUndo(item) { toast = $0 }
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
                    Text(PantryQuantityFormatter.text(quantity: item.quantity, unit: item.unit))
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
                    list.exportedToReminders ? String(localized: "Re-export to Reminders") : String(localized: "Export to Reminders"),
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
        let generating = viewModel.groceryState.isGenerating
        return KitchenStatePage(actions: [
            KitchenStateAction(
                title: generating ? String(localized: "Generating…") : String(localized: "Generate"),
                systemImage: "wand.and.stars",
                role: .primary,
                isEnabled: !generating
            ) { viewModel.generateGroceryList() },
        ]) {
            VStack(spacing: Tide.s4) {
                KitchenStateHero(
                    systemImage: "cart",
                    title: String(localized: "No grocery list yet"),
                    message: String(localized: "Generate a meal plan first, then tap Generate to build your shopping list.")
                )
                if let error = viewModel.groceryState.lastError {
                    KitchenNotice(systemImage: "exclamationmark.triangle.fill", text: error, tint: Tide.danger)
                }
            }
        }
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
                KitchenFormSection(String(localized: "Item")) {
                    TextField("Name (e.g. olive oil)", text: $name)
                        .textInputAutocapitalization(.never)
                }
                KitchenFormSection(String(localized: "Quantity")) {
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

// MARK: - Aisle names

/// Grocery categories are stored as lowercase English keys ("produce", "dairy"); this is the name
/// the shopping list and Store Mode show. A key it does not know is shown as it is.
enum GroceryAisleName {
    static func display(_ category: String) -> String {
        switch category {
        case "produce": String(localized: "produce")
        case "grains": String(localized: "grains")
        case "meat": String(localized: "meat")
        case "seafood": String(localized: "seafood")
        case "protein": String(localized: "protein")
        case "dairy": String(localized: "dairy")
        case "frozen": String(localized: "frozen")
        case "oils": String(localized: "oils")
        case "pantry": String(localized: "pantry")
        default: category
        }
    }
}
