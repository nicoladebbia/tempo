//
// GroceryStoreModeView.swift
// Tempo
//
// Full-screen "in the store" mode (BUILD item 2): big tap targets, keeps the
// screen awake, shows trip progress, collapses finished aisles, and ends
// with a prominent "Done shopping" button that hands off to the
// bought → pantry review sheet.
//
// Built for one hand in an aisle: the whole row is the button, names are
// large, and the way out sits under the thumb.
//

import SwiftUI

struct GroceryStoreModeView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    let list: GroceryList
    /// Called when "Done shopping" is tapped — the caller (GroceryListView)
    /// dismisses this and presents GroceryDoneShoppingView.
    var onDoneShopping: () -> Void

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    /// Categories the user has collapsed manually, IN ADDITION TO the
    /// auto-collapse of fully-checked aisles below.
    @State
    private var manuallyExpanded: Set<String> = []
    @State
    private var ticks = 0

    private var orderedCategories: [String] {
        viewModel.resolvedGroceryCategoryOrder(for: list)
    }

    private func items(for category: String) -> [GroceryListItem] {
        list.activeItems.filter { $0.category == category }
    }

    private var totalCount: Int {
        list.itemCount
    }

    private var checkedCount: Int {
        list.checkedCount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    progressHeader
                    ForEach(orderedCategories, id: \.self) { category in
                        aisleSection(category: category, items: items(for: category))
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .kitchenPage(energy: 1)
            .kitchenBottomBar {
                doneShoppingButton
            }
            .sensoryFeedback(.impact(weight: .light), trigger: ticks)
            .navigationTitle("Store Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Exit") {
                        viewModel.commitGroceryStoreModeSession()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.commitGroceryStoreModeSession()
        }
    }

    // MARK: - Progress

    private var progressHeader: some View {
        let total = max(1, totalCount)
        let progress = Double(checkedCount) / Double(total)
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideNumber(
                "\(checkedCount)", unit: "of \(totalCount) checked off",
                size: Tide.numeralL, relativeTo: .largeTitle
            )
            TideLevelBar(progress: progress, color: mood.accent, height: Tide.bar)
                .animation(Tide.settle, value: progress)
                .accessibilityLabel("Checked off")
        }
        .padding(.horizontal, Tide.s1)
        .padding(.top, Tide.s2)
    }

    // MARK: - Aisle section (collapses when fully checked)

    private func aisleSection(category: String, items: [GroceryListItem]) -> some View {
        let isComplete = !items.isEmpty && items.allSatisfy(\.isChecked)
        let isExpanded = !isComplete || manuallyExpanded.contains(category)

        return VStack(alignment: .leading, spacing: Tide.s2) {
            Button {
                if isComplete {
                    withAnimation(Tide.snap) {
                        if manuallyExpanded.contains(category) {
                            manuallyExpanded.remove(category)
                        } else {
                            manuallyExpanded.insert(category)
                        }
                    }
                }
            } label: {
                HStack(spacing: Tide.s2) {
                    Text(category).tideLabel(isComplete ? Tide.Kitchen.good : Tide.text2)
                    if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Tide.label)
                            .foregroundStyle(Tide.Kitchen.good)
                    }
                    Spacer(minLength: Tide.s2)
                    if isComplete {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(Tide.label)
                            .foregroundStyle(Tide.text3)
                    }
                }
                .padding(.horizontal, Tide.s1)
                .frame(minHeight: Tide.hit)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(isComplete ? (isExpanded ? "Collapse" : "Expand") : "")

            if isExpanded {
                KitchenRows {
                    ForEach(items, id: \.id) { item in
                        storeModeRow(item)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Big-tap-target row

    private func storeModeRow(_ item: GroceryListItem) -> some View {
        Button {
            viewModel.toggleGroceryItem(item)
            ticks += 1
            if item.isChecked {
                viewModel.recordGroceryCategoryTick(item.category)
            }
        } label: {
            HStack(spacing: Tide.s4) {
                KitchenCheck(checked: item.isChecked, size: Tide.s10)
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(item.displayName)
                        .font(Tide.Kitchen.shopName)
                        .foregroundStyle(item.isChecked ? Tide.text3 : Tide.text)
                        .strikethrough(item.isChecked)
                        .fixedSize(horizontal: false, vertical: true)
                    // "4 breasts chicken" already carries its amount.
                    if !item.displayNameEmbedsQuantity {
                        Text("\(formatQuantity(item.quantity))\(item.unit.displayName)")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: Tide.Kitchen.shopRow - Tide.s3 * 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(item.isChecked ? "Checked" : "Not checked")
    }

    // MARK: - Done shopping

    private var doneShoppingButton: some View {
        Button {
            HapticManager.notification(.success)
            onDoneShopping()
        } label: {
            Label("Done Shopping", systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(.tidePrimary)
        .disabled(checkedCount == 0)
    }

    private func formatQuantity(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
