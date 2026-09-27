//
// GroceryWeeklySpendView.swift
// Tempo
//
// Weekly spend history (BUILD item 4): actual spend per week (from
// PantryPriceEntry + Receipts) vs. the budget cap, for the last ~8 weeks.
// Simple bar-per-week rows in the app's existing progress-bar visual
// language (see GroceryListView.progressBar) rather than a chart library —
// Tempo ships only 3 third-party deps and none of them is a chart kit.
//

import SwiftUI

// MARK: - GroceryWeeklySpendView

struct GroceryWeeklySpendView: View {
    @Bindable
    var viewModel: NutritionTabViewModel

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    if viewModel.groceryStoreModeState.weeklySpend.isEmpty {
                        Text("No purchases recorded yet.")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .padding(.top, TempoSpacing.xxxl)
                    } else {
                        ForEach(viewModel.groceryStoreModeState.weeklySpend.reversed()) { week in
                            weekRow(week)
                        }
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Spend History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            viewModel.loadGroceryWeeklySpendHistory()
        }
    }

    private func weekRow(_ week: GroceryWeeklySpend) -> some View {
        let cap = week.budgetCapUSD.map(Double.init)
        let fraction = cap.map { min(1, week.totalUSD / max(1, $0)) } ?? 0
        return VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack {
                Text(week.weekStartDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                Text("$" + String(format: "%.2f", week.totalUSD))
                    .font(.tempoBodyBold)
                    .foregroundStyle(week.isOverBudget ? Color.tempoError : Color.tempoTextPrimary)
                if let cap = week.budgetCapUSD {
                    Text("/ $\(cap)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            if cap != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.tempoBorder.opacity(0.5)).frame(height: 8)
                        Capsule()
                            .fill(week.isOverBudget ? Color.tempoError : Color.tempoSignal)
                            .frame(width: geo.size.width * fraction, height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }
}

// MARK: - CheaperSwapsSheet

/// Simple bullet-list sheet for the "Cheaper swaps" suggestions surfaced
/// when the list is over budget.
struct CheaperSwapsSheet: View {
    @Bindable
    var viewModel: NutritionTabViewModel

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    if viewModel.groceryStoreModeState.isFetchingSwaps {
                        ProgressView("Thinking of cheaper swaps…")
                            .padding(.top, TempoSpacing.xxxl)
                    } else if let error = viewModel.groceryStoreModeState.swapsError {
                        Text(error)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoError)
                    } else if viewModel.groceryStoreModeState.cheaperSwaps.isEmpty {
                        Text("No swaps to suggest — the list is lean already.")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                    } else {
                        ForEach(viewModel.groceryStoreModeState.cheaperSwaps, id: \.self) { swap in
                            HStack(alignment: .top, spacing: TempoSpacing.sm) {
                                Image(systemName: "arrow.triangle.swap")
                                    .foregroundStyle(Color.tempoSignal)
                                Text(swap)
                                    .font(.tempoBody)
                                    .foregroundStyle(Color.tempoTextPrimary)
                            }
                            .padding(TempoSpacing.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.tempoSurfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Cheaper Swaps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
