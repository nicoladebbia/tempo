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
        Array(Set(list.orderedItems.map(\.category))).sorted()
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
