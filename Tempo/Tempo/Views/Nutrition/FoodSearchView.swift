//
// FoodSearchView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - FoodSearchView

// Searchable food list with local cache + USDA API fallback.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant empty states.

struct FoodSearchView: View {
    var onFoodSelected: ((FoodItem) -> Void)?

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var searchText = ""
    @State
    private var selectedTab: SearchTab = .all
    @State
    private var searchResults: [SearchableFoodItem] = []
    @State
    private var recentFoods: [SearchableFoodItem] = SearchableFoodItem.mockRecents
    @State
    private var favoriteFoods: [SearchableFoodItem] = SearchableFoodItem.mockFavorites
    @State
    private var isLoading = false
    @State
    private var hasSearched = false
    @State
    private var errorMessage: String?
    @State
    private var selectedFood: SearchableFoodItem?
    @State
    private var portionQuantity: Double = 1.0

    enum SearchTab: String, CaseIterable, Identifiable {
        case all = "All"
        case recent = "Recent"
        case favorites = "Favorites"

        var id: String {
            rawValue
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Filter", selection: $selectedTab) {
                    ForEach(SearchTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.sm)
                .onChange(of: selectedTab) { _, _ in
                    HapticManager.selection()
                }

                // Content
                Group {
                    switch selectedTab {
                    case .all:
                        allTabContent
                    case .recent:
                        recentTabContent
                    case .favorites:
                        favoritesTabContent
                    }
                }
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Search Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .searchable(text: $searchText, prompt: "Search for a food")
            .onSubmit(of: .search) {
                performSearch()
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty {
                    searchResults = []
                    hasSearched = false
                    errorMessage = nil
                }
            }
            .sheet(item: $selectedFood) { food in
                portionPickerSheet(food: food)
            }
        }
    }

    // MARK: - All Tab

    private var allTabContent: some View {
        Group {
            if isLoading {
                LoadingStateView(style: .list)
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.top, TempoSpacing.lg)
            } else if let errorMessage {
                errorState(message: errorMessage)
            } else if searchResults.isEmpty, hasSearched {
                noResultsState
            } else if searchResults.isEmpty {
                searchEmptyState
            } else {
                resultsList(searchResults)
            }
        }
    }

    // MARK: - Recent Tab

    private var recentTabContent: some View {
        Group {
            if recentFoods.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: "No Recent Foods",
                    message: "Foods you log will show up here for quick access."
                )
            } else {
                resultsList(filteredRecents)
            }
        }
    }

    // MARK: - Favorites Tab

    private var favoritesTabContent: some View {
        Group {
            if favoriteFoods.isEmpty {
                EmptyStateView(
                    icon: "heart",
                    title: "No Favorites Yet",
                    message: "Mark foods as favorites for quick access."
                )
            } else {
                resultsList(filteredFavorites)
            }
        }
    }

    // MARK: - Results List

    private func resultsList(_ items: [SearchableFoodItem]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    Button {
                        selectedFood = item
                        HapticManager.lightImpact()
                    } label: {
                        foodResultRow(item)
                    }
                    .buttonStyle(.plain)

                    if item.id != items.last?.id {
                        Divider()
                            .background(Color.tempoDivider)
                            .padding(.leading, TempoSpacing.screenEdge)
                    }
                }
            }
        }
    }

    private func foodResultRow(_ item: SearchableFoodItem) -> some View {
        HStack(spacing: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(item.name)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)

                HStack(spacing: TempoSpacing.sm) {
                    if let brand = item.brand {
                        Text(brand)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }

                    Text("per \(item.servingSize)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: TempoSpacing.xxs) {
                Text("\(item.caloriesPerServing) kcal")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextPrimary)

                HStack(spacing: TempoSpacing.sm) {
                    Text("P:\(Int(item.proteinPerServing))g")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoMacroProtein)
                    Text("C:\(Int(item.carbsPerServing))g")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoMacroCarbs)
                    Text("F:\(Int(item.fatPerServing))g")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoMacroFat)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.listItemVertical)
    }

    // MARK: - Portion Picker Sheet

    private func portionPickerSheet(food: SearchableFoodItem) -> some View {
        NavigationStack {
            VStack(spacing: TempoSpacing.xxl) {
                // Food info header — shown as the inline title via navigationTitle.
                if let brand = food.brand {
                    Text(brand)
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .padding(.top, TempoSpacing.sm)
                }

                // Serving info
                VStack(spacing: TempoSpacing.md) {
                    Text("SERVINGS")
                        .font(.tempoModuleTag)
                        .tracking(TempoTracking.moduleTag)
                        .foregroundStyle(Color.tempoTextSecondary)

                    HStack(spacing: TempoSpacing.lg) {
                        NumberStepperView(
                            value: $portionQuantity,
                            range: 0.5 ... 10,
                            step: 0.5,
                            format: "%.1f",
                            unit: "x"
                        )
                    }

                    Text(food.servingSize)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                // Calculated macros
                macroPreviewCard(food: food)

                Spacer()

                // Add button
                Button {
                    addToMeal(food: food)
                } label: {
                    Text("Add to Meal")
                }
                .buttonStyle(.tempoPrimary)
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, TempoSpacing.bottomSafe)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .background(Color.tempoBgPrimary)
            .navigationTitle(food.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selectedFood = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func macroPreviewCard(food: SearchableFoodItem) -> some View {
        let multiplier = portionQuantity
        return VStack(spacing: TempoSpacing.md) {
            HStack {
                Text("Calories")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Text("\(Int(Double(food.caloriesPerServing) * multiplier)) kcal")
                    .font(.tempoDataMedium)
                    .foregroundStyle(Color.tempoViolet)
            }

            Divider().background(Color.tempoDivider)

            macroPreviewRow(
                label: "Protein",
                value: food.proteinPerServing * multiplier,
                color: Color.tempoMacroProtein
            )
            macroPreviewRow(
                label: "Carbs",
                value: food.carbsPerServing * multiplier,
                color: Color.tempoMacroCarbs
            )
            macroPreviewRow(
                label: "Fat",
                value: food.fatPerServing * multiplier,
                color: Color.tempoMacroFat
            )
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func macroPreviewRow(label: String, value: Double, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Text("\(Int(value))g")
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    // MARK: - Empty / Error States

    private var searchEmptyState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "Search for a food",
            message: "Search for a food or scan a barcode."
        )
    }

    private var noResultsState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No results",
            message: "Try a different search term or scan a barcode."
        )
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.tempoAsh)

            Text("Search failed")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .padding(.top, TempoSpacing.lg)

            Text(message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, TempoSpacing.sm)

            Button("Retry") {
                performSearch()
            }
            .buttonStyle(.tempoPrimary)
            .padding(.horizontal, TempoSpacing.xxxxl)
            .padding(.top, TempoSpacing.xxl)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Filtering

    private var filteredRecents: [SearchableFoodItem] {
        guard !searchText.isEmpty else {
            return recentFoods
        }
        return recentFoods.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredFavorites: [SearchableFoodItem] {
        guard !searchText.isEmpty else {
            return favoriteFoods
        }
        return favoriteFoods.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        isLoading = true
        hasSearched = true
        errorMessage = nil

        // Simulated search — in production, hits local CachedFood first then USDA API
        Task {
            try? await Task.sleep(for: .milliseconds(800))

            // Mock results
            searchResults = SearchableFoodItem.mockSearchResults(for: searchText)
            isLoading = false

            if searchResults.isEmpty {
                // No error — just no results
            }
        }
    }

    private func addToMeal(food: SearchableFoodItem) {
        let multiplier = portionQuantity
        let item = FoodItem(
            id: UUID(),
            name: food.name,
            brand: food.brand,
            servingSize: food.servingSize,
            servingQuantity: portionQuantity,
            calories: Int(Double(food.caloriesPerServing) * multiplier),
            protein: food.proteinPerServing * multiplier,
            carbs: food.carbsPerServing * multiplier,
            fat: food.fatPerServing * multiplier
        )
        HapticManager.notification(.success)
        onFoodSelected?(item)
        selectedFood = nil
        portionQuantity = 1.0
        dismiss()
    }
}

// MARK: - SearchableFoodItem

struct SearchableFoodItem: Identifiable {
    let id: UUID
    let name: String
    let brand: String?
    let servingSize: String
    let caloriesPerServing: Int
    let proteinPerServing: Double
    let carbsPerServing: Double
    let fatPerServing: Double
    let isFavorite: Bool

    // MARK: - Mock Data

    static let mockRecents: [SearchableFoodItem] = [
        SearchableFoodItem(
            id: UUID(),
            name: "Chicken Breast",
            brand: nil,
            servingSize: "150g",
            caloriesPerServing: 248,
            proteinPerServing: 46,
            carbsPerServing: 0,
            fatPerServing: 5.4,
            isFavorite: false
        ),
        SearchableFoodItem(
            id: UUID(),
            name: "Brown Rice",
            brand: nil,
            servingSize: "200g cooked",
            caloriesPerServing: 220,
            proteinPerServing: 5,
            carbsPerServing: 46,
            fatPerServing: 1.8,
            isFavorite: false
        ),
        SearchableFoodItem(
            id: UUID(),
            name: "Protein Shake",
            brand: "Optimum Nutrition",
            servingSize: "1 scoop (30g)",
            caloriesPerServing: 120,
            proteinPerServing: 24,
            carbsPerServing: 3,
            fatPerServing: 1.5,
            isFavorite: true
        ),
    ]

    static let mockFavorites: [SearchableFoodItem] = [
        SearchableFoodItem(
            id: UUID(),
            name: "Protein Shake",
            brand: "Optimum Nutrition",
            servingSize: "1 scoop (30g)",
            caloriesPerServing: 120,
            proteinPerServing: 24,
            carbsPerServing: 3,
            fatPerServing: 1.5,
            isFavorite: true
        ),
        SearchableFoodItem(
            id: UUID(),
            name: "Eggs",
            brand: nil,
            servingSize: "1 large (50g)",
            caloriesPerServing: 72,
            proteinPerServing: 6.3,
            carbsPerServing: 0.4,
            fatPerServing: 4.8,
            isFavorite: true
        ),
        SearchableFoodItem(
            id: UUID(),
            name: "Oats",
            brand: nil,
            servingSize: "40g dry",
            caloriesPerServing: 150,
            proteinPerServing: 5,
            carbsPerServing: 27,
            fatPerServing: 2.5,
            isFavorite: true
        ),
    ]

    static func mockSearchResults(for query: String) -> [SearchableFoodItem] {
        let all = [
            SearchableFoodItem(
                id: UUID(),
                name: "Chicken Breast (grilled)",
                brand: nil,
                servingSize: "150g",
                caloriesPerServing: 248,
                proteinPerServing: 46,
                carbsPerServing: 0,
                fatPerServing: 5.4,
                isFavorite: false
            ),
            SearchableFoodItem(
                id: UUID(),
                name: "Chicken Thigh (skin-on)",
                brand: nil,
                servingSize: "130g",
                caloriesPerServing: 280,
                proteinPerServing: 28,
                carbsPerServing: 0,
                fatPerServing: 18,
                isFavorite: false
            ),
            SearchableFoodItem(
                id: UUID(),
                name: "Greek Yogurt 0%",
                brand: "Fage",
                servingSize: "170g",
                caloriesPerServing: 100,
                proteinPerServing: 18,
                carbsPerServing: 6,
                fatPerServing: 0.7,
                isFavorite: false
            ),
            SearchableFoodItem(
                id: UUID(),
                name: "Banana",
                brand: nil,
                servingSize: "1 medium (118g)",
                caloriesPerServing: 105,
                proteinPerServing: 1.3,
                carbsPerServing: 27,
                fatPerServing: 0.4,
                isFavorite: false
            ),
            SearchableFoodItem(
                id: UUID(),
                name: "Salmon Fillet",
                brand: nil,
                servingSize: "150g",
                caloriesPerServing: 310,
                proteinPerServing: 34,
                carbsPerServing: 0,
                fatPerServing: 18,
                isFavorite: false
            ),
            SearchableFoodItem(
                id: UUID(),
                name: "Sweet Potato",
                brand: nil,
                servingSize: "200g baked",
                caloriesPerServing: 180,
                proteinPerServing: 4,
                carbsPerServing: 41,
                fatPerServing: 0.2,
                isFavorite: false
            ),
        ]
        if query.isEmpty {
            return all
        }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

// MARK: - Preview

#Preview {
    FoodSearchView()
}
