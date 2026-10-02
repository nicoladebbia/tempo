//
// GroceryStoreModeView.swift
// Tempo
//
// Full-screen "in the store" mode (BUILD item 2): big tap targets, keeps the
// screen awake, shows trip progress, collapses finished aisles, and ends
// with a prominent "Done shopping" button that hands off to the
// bought → pantry review sheet.
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

    /// Categories the user has collapsed manually, IN ADDITION TO the
    /// auto-collapse of fully-checked aisles below.
    @State
    private var manuallyExpanded: Set<String> = []

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
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    progressHeader
                    ForEach(orderedCategories, id: \.self) { category in
                        aisleSection(category: category, items: items(for: category))
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
                .padding(.bottom, TempoSpacing.xxxxxl)
            }
            .background(Color.tempoBgPrimary)
            .safeAreaInset(edge: .bottom) {
                doneShoppingButton
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.vertical, TempoSpacing.md)
                    .background(.ultraThinMaterial)
            }
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
        return VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("\(checkedCount) of \(totalCount) checked off")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.tempoBorder.opacity(0.5)).frame(height: 10)
                    Capsule().fill(Color.tempoSignal).frame(width: geo.size.width * progress, height: 10)
                }
            }
            .frame(height: 10)
        }
    }

    // MARK: - Aisle section (collapses when fully checked)

    private func aisleSection(category: String, items: [GroceryListItem]) -> some View {
        let isComplete = !items.isEmpty && items.allSatisfy(\.isChecked)
        let isExpanded = !isComplete || manuallyExpanded.contains(category)

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Button {
                if isComplete {
                    if manuallyExpanded.contains(category) {
                        manuallyExpanded.remove(category)
                    } else {
                        manuallyExpanded.insert(category)
                    }
                }
            } label: {
                HStack {
                    Text(category.uppercased())
                        .font(.tempoModuleTag)
                        .foregroundStyle(isComplete ? Color.tempoSuccess : Color.tempoTextSecondary)
                    if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.tempoSuccess)
                    }
                    Spacer()
                    if isComplete {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(items, id: \.id) { item in
                    storeModeRow(item)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Big-tap-target row

    private func storeModeRow(_ item: GroceryListItem) -> some View {
        Button {
            viewModel.toggleGroceryItem(item)
            HapticManager.lightImpact()
            if item.isChecked {
                viewModel.recordGroceryCategoryTick(item.category)
            }
        } label: {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(item.isChecked ? Color.tempoSuccess : Color.tempoTextTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .strikethrough(item.isChecked)
                    // "4 breasts chicken" already carries its amount.
                    if !item.displayNameEmbedsQuantity {
                        Text("\(formatQuantity(item.quantity))\(item.unit.displayName)")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                Spacer()
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Done shopping

    private var doneShoppingButton: some View {
        Button {
            HapticManager.notification(.success)
            onDoneShopping()
        } label: {
            Label("Done Shopping", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tempoPrimary)
        .disabled(checkedCount == 0)
    }

    private func formatQuantity(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
