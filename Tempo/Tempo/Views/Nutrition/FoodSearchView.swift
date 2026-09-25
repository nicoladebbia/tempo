//
// FoodSearchView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - FoodSearchView

// Real food search through FoodCatalog: your own products (history,
// favourites, added), basic foods (Tempo's table + USDA via the backend) and
// packaged products (Open Food Facts), each with its Tempo score. Tapping a
// result opens the product screen. With `onFoodSelected` the product screen
// offers "Add to meal"; without it it's look-only.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant empty states.

struct FoodSearchView: View {
    var onFoodSelected: ((FoodItem) -> Void)?
    /// Optional pre-filled query (e.g. from a low-confidence voice item's
    /// "Search instead" fallback). Defaults to empty for existing callers.
    var initialQuery: String?

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    @Query(sort: \ScannedFood.lastViewedAt, order: .reverse)
    private var saved: [ScannedFood]

    @State
    private var searchText = ""
    @State
    private var selectedTab: SearchTab = .all
    @State
    private var results = FoodCatalog.SearchResults()
    @State
    private var isLoading = false
    @State
    private var hasSearched = false
    @State
    private var showScanner = false
    @State
    private var catalog: FoodCatalog?

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
                Picker("Tab", selection: $selectedTab) {
                    ForEach(SearchTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.sm)

                if let catalog {
                    switch selectedTab {
                    case .all:
                        allTabContent(catalog)
                    case .recent:
                        savedList(filteredRecents, catalog: catalog, empty: "Nothing scanned or opened yet.")
                    case .favorites:
                        savedList(filteredFavorites, catalog: catalog, empty: "No favourites yet. Tap the star on a product.")
                    }
                }
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Search Food")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Foods or brands — e.g. skyr, Barilla"
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel("Scan a barcode")
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView(onFoodScanned: onFoodSelected.map { handler in
                    { item in
                        handler(item)
                        dismiss()
                    }
                })
            }
            .task(id: searchText) {
                await runSearch()
            }
            .onAppear {
                if catalog == nil {
                    catalog = FoodCatalog(services: services)
                }
                if searchText.isEmpty, let initialQuery, !initialQuery.isEmpty {
                    searchText = initialQuery
                }
            }
        }
    }

    // MARK: - All tab

    @ViewBuilder
    private func allTabContent(_ catalog: FoodCatalog) -> some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.count < 2 {
            if filteredRecents.isEmpty {
                searchEmptyState
            } else {
                savedList(Array(filteredRecents.prefix(15)), catalog: catalog, empty: "", header: "RECENT")
            }
        } else if results.isEmpty, isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty, hasSearched {
            noResultsState
        } else {
            List {
                if !results.notices.isEmpty {
                    Section {
                        ForEach(results.notices, id: \.self) { notice in
                            Label(notice, systemImage: "exclamationmark.triangle")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoAmber)
                        }
                    }
                }
                resultSection("YOURS", results.yours, catalog: catalog)
                resultSection("BASIC FOODS", results.basics, catalog: catalog)
                resultSection("PACKAGED PRODUCTS", results.products, catalog: catalog)
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func resultSection(_ title: String, _ products: [FoodProduct], catalog: FoodCatalog) -> some View {
        if !products.isEmpty {
            Section(title) {
                ForEach(products) { product in
                    NavigationLink {
                        FoodProductView(product: product, mode: productMode, catalog: catalog)
                    } label: {
                        FoodProductRow(product: product)
                    }
                    .listRowBackground(Color.tempoSurfaceCard)
                }
            }
        }
    }

    // MARK: - Recent / favourites

    @ViewBuilder
    private func savedList(_ rows: [ScannedFood], catalog: FoodCatalog, empty: String, header: String? = nil) -> some View {
        if rows.isEmpty {
            Text(empty)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(TempoSpacing.xxl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(rows) { row in
                        if let product = row.product {
                            NavigationLink {
                                FoodProductView(product: product, mode: productMode, catalog: catalog)
                            } label: {
                                FoodProductRow(product: product, photo: row.photoData)
                            }
                            .listRowBackground(Color.tempoSurfaceCard)
                        }
                    }
                } header: {
                    if let header {
                        Text(header)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Empty States

    private var searchEmptyState: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "Find any food",
            message: "Search basics like \"chicken breast\" or packaged products by name or brand. Or scan a barcode."
        )
    }

    private var noResultsState: some View {
        EmptyStateView(
            icon: "fork.knife",
            title: "Nothing found",
            message: "Try a shorter name, or scan the barcode.",
            actionTitle: "Scan a barcode"
        ) {
            showScanner = true
        }
    }

    // MARK: - Helpers

    private var productMode: FoodProductView.Mode {
        guard let onFoodSelected else {
            return .check
        }
        return .log { item in
            onFoodSelected(item)
            dismiss()
        }
    }

    private var filteredRecents: [ScannedFood] {
        filter(saved)
    }

    private var filteredFavorites: [ScannedFood] {
        filter(saved.filter(\.isFavorite)).sorted { $0.name < $1.name }
    }

    private func filter(_ rows: [ScannedFood]) -> [ScannedFood] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return rows
        }
        return rows.filter { $0.searchText.contains(query) }
    }

    /// Debounced: local results immediately, network sources after a short pause.
    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, let catalog else {
            results = FoodCatalog.SearchResults()
            hasSearched = false
            isLoading = false
            return
        }
        results = catalog.localResults(for: query, in: modelContext)
        isLoading = true
        do {
            try await Task.sleep(for: .milliseconds(400))
        } catch {
            return
        }
        let found = await catalog.search(query, in: modelContext)
        guard !Task.isCancelled else {
            return
        }
        results = found
        hasSearched = true
        isLoading = false
    }
}

// MARK: - Preview

#Preview {
    FoodSearchView()
        .environment(ServiceContainer.mock())
        .modelContainer(for: [ScannedFood.self], inMemory: true)
}
