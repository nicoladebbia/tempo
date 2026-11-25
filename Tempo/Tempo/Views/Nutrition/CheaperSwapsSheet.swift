//
// CheaperSwapsSheet.swift
// Tempo
//
// The "Cheaper swaps" suggestions the Groceries page offers when the list is
// over budget.
//

import SwiftUI

// MARK: - CheaperSwapsSheet

/// Simple list sheet for the "Cheaper swaps" suggestions surfaced
/// when the list is over budget.
struct CheaperSwapsSheet: View {
    @Bindable
    var viewModel: NutritionTabViewModel

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s3) {
                    if viewModel.groceryStoreModeState.isFetchingSwaps {
                        // The shape of the answer, shimmering, with the line that says what is happening.
                        VStack(alignment: .leading, spacing: Tide.s3) {
                            VStack(spacing: Tide.s3) {
                                ForEach(0 ..< 3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
                                        .fill(Tide.fill)
                                        .frame(height: Tide.Kitchen.row + Tide.s4)
                                }
                            }
                            .shimmer()
                            Text("Thinking of cheaper swaps…")
                                .font(Tide.body)
                                .foregroundStyle(Tide.text2)
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Thinking of cheaper swaps")
                    } else if let error = viewModel.groceryStoreModeState.swapsError {
                        KitchenFailure(
                            title: "Couldn't find swaps",
                            message: error,
                            retry: { Task { await viewModel.fetchCheaperSwaps() } }
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, Tide.s6)
                    } else if viewModel.groceryStoreModeState.cheaperSwaps.isEmpty {
                        KitchenEmpty(
                            systemImage: "checkmark.seal",
                            title: "Nothing to swap",
                            message: "The list is lean already."
                        )
                    } else {
                        ForEach(viewModel.groceryStoreModeState.cheaperSwaps, id: \.self) { swap in
                            HStack(alignment: .top, spacing: Tide.s3) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(Tide.bodyStrong)
                                    .foregroundStyle(mood.accent)
                                    .accessibilityHidden(true)
                                Text(swap)
                                    .font(Tide.body)
                                    .foregroundStyle(Tide.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tideCard(padding: Tide.s4)
                        }
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s4)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Cheaper Swaps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .kitchenSheet()
    }
}
