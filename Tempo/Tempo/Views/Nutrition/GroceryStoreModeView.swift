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
// large, the next thing to pick up is lit, and the way out sits under the
// thumb. Ticking an item fills its circle, strikes its name and moves the
// bar; finishing an aisle folds it away.
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
    /// "Milk checked off" with its Undo. Kept here: this cover sits over the Fuel toast host.
    @State
    private var toast: ToastData?

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

    /// The first thing still to pick up, in the order of the aisles.
    private var nextItemID: UUID? {
        for category in orderedCategories {
            if let item = items(for: category).first(where: { !$0.isChecked }) {
                return item.id
            }
        }
        return nil
    }

    /// How many aisles are finished: a new one is a small win worth a buzz.
    private var finishedAisles: Int {
        orderedCategories.filter { category in
            let rows = items(for: category)
            return !rows.isEmpty && rows.allSatisfy(\.isChecked)
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    progressHeader
                    if totalCount == 0 {
                        KitchenEmpty(
                            systemImage: "cart",
                            title: String(localized: "Nothing left to buy"),
                            message: String(localized: "The list is empty. Add items on the Groceries list, then come back.")
                        )
                    }
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
            // Before the bottom bar, so the toast rests above "Done shopping", not on it, and
            // takes its own room: a floating toast sits on the big rows, and a tap on its Undo
            // would tick the row under it.
            .kitchenToast($toast)
            .kitchenBottomBar {
                doneShoppingButton
            }
            .firstTip("fuel.store-mode", "Tap each item as it goes in your basket.")
            .sensoryFeedback(.impact(flexibility: .solid), trigger: ticks)
            .sensoryFeedback(.success, trigger: finishedAisles) { old, new in new > old }
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
        let allDone = totalCount > 0 && checkedCount == totalCount
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(
                title: String(localized: "Your trip"),
                trailing: allDone ? String(localized: "All checked") : String(localized: "\(max(totalCount - checkedCount, 0)) left")
            )
            TideNumber(
                "\(checkedCount)", unit: String(localized: "of \(totalCount) checked off"),
                size: Tide.numeralL, relativeTo: .largeTitle,
                color: allDone ? Tide.Kitchen.good : Tide.text
            )
            TideLevelBar(progress: progress, color: allDone ? Tide.Kitchen.good : mood.accent, height: Tide.bar)
                .animation(Tide.settle, value: progress)
                .accessibilityLabel("Checked off")
        }
        .tideCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Aisle section (collapses when fully checked)

    private func aisleSection(category: String, items: [GroceryListItem]) -> some View {
        let isComplete = !items.isEmpty && items.allSatisfy(\.isChecked)
        let isExpanded = !isComplete || manuallyExpanded.contains(category)
        let left = items.filter { !$0.isChecked }.count

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
                    Text(GroceryAisleName.display(category)).tideLabel(isComplete ? Tide.Kitchen.good : Tide.text2)
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
                    } else if !items.isEmpty {
                        Text("\(left) left")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, Tide.s1)
                .frame(minHeight: Tide.hit)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(isComplete ? (isExpanded ? String(localized: "Collapse") : String(localized: "Expand")) : "")

            if isExpanded {
                aisleRows(items)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(.top, isExpanded ? Tide.s2 : 0)
        .animation(Tide.snap, value: isExpanded)
    }

    /// One glass card per aisle; the row to pick up next is lit.
    private func aisleRows(_ items: [GroceryListItem]) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Tide.hairline)
                        .frame(height: 1)
                        .padding(.leading, Tide.s4)
                        .accessibilityHidden(true)
                }
                storeModeRow(item, isNext: item.id == nextItemID)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(shape)
        .glassEffect(.regular.tint(Tide.glassCard), in: shape)
    }

    // MARK: - Big-tap-target row

    private func storeModeRow(_ item: GroceryListItem, isNext: Bool) -> some View {
        Button {
            toast = viewModel.toggleGroceryItemWithUndo(item)
            ticks += 1
            if item.isChecked {
                viewModel.recordGroceryCategoryTick(item.category)
            }
        } label: {
            HStack(spacing: Tide.s4) {
                KitchenCheck(checked: item.isChecked, size: Tide.s10)
                VStack(alignment: .leading, spacing: Tide.s1) {
                    if isNext {
                        Text(String(localized: "store-mode.next", defaultValue: "Next", comment: "Tag on the next item to pick up in store mode (not the Next button)")).tideLabel(mood.accent)
                    }
                    Text(item.displayName)
                        .font(Tide.Kitchen.shopName)
                        .foregroundStyle(item.isChecked ? Tide.text3 : Tide.text)
                        .strikethrough(item.isChecked)
                        .fixedSize(horizontal: false, vertical: true)
                    // "4 breasts chicken" already carries its amount.
                    if !item.displayNameEmbedsQuantity {
                        Text(PantryQuantityFormatter.text(quantity: item.quantity, unit: item.unit))
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tide.s4)
            .padding(.vertical, Tide.s3)
            .frame(maxWidth: .infinity, minHeight: Tide.Kitchen.shopRow, alignment: .leading)
            .background(isNext ? mood.accent.opacity(0.14) : Color.clear)
            .overlay(alignment: .leading) {
                if isNext {
                    Capsule()
                        .fill(mood.accent)
                        .frame(width: Tide.s1)
                        .padding(.vertical, Tide.s3)
                        .padding(.leading, Tide.hair)
                }
            }
            .animation(Tide.snap, value: isNext)
            .contentShape(.rect)
        }
        .buttonStyle(KitchenRowPressStyle())
        .accessibilityValue(item.isChecked ? String(localized: "Checked") : String(localized: "Not checked"))
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
}
