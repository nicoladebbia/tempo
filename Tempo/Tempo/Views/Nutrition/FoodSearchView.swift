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
    /// Opens straight into typing — the user came here to search.
    @State
    private var isSearchPresented = false
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
    /// Next Open Food Facts page to fetch when the user scrolls to the end.
    @State
    private var nextPage = 2
    @State
    private var canLoadMore = false
    @State
    private var isLoadingMore = false

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
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s2)
                .sensoryFeedback(.selection, trigger: selectedTab)

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
            .tidePage()
            .tideCovered(showScanner)
            .navigationTitle("Search Food")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Foods or brands — e.g. skyr, Barilla"
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
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
                UniversalScanView(context: .foodSearch(onFood: onFoodSelected.map { handler in
                    { item in
                        handler(item)
                        dismiss()
                    }
                }))
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
                } else if searchText.isEmpty {
                    isSearchPresented = true
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
                savedList(Array(filteredRecents.prefix(15)), catalog: catalog, empty: "", header: "Recent")
            }
        } else if results.isEmpty, isLoading {
            ProgressView()
                .tint(Tide.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty, hasSearched {
            noResultsState
        } else {
            List {
                if !results.notices.isEmpty {
                    Section {
                        ForEach(results.notices, id: \.self) { notice in
                            Label(notice, systemImage: "exclamationmark.triangle")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.warn)
                                .fuelRow()
                        }
                    }
                }
                resultSection("Yours", results.yours, catalog: catalog)
                resultSection("Basic foods", results.basics, catalog: catalog)
                resultSection("Packaged products", results.products, catalog: catalog)
                if isLoading || isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(Tide.text2)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func resultSection(_ title: String, _ products: [FoodProduct], catalog: FoodCatalog) -> some View {
        if !products.isEmpty {
            Section {
                ForEach(products) { product in
                    NavigationLink {
                        FoodProductView(product: product, mode: productMode, catalog: catalog)
                    } label: {
                        FoodProductRow(product: product)
                    }
                    .fuelRow()
                    .onAppear {
                        if product.id == results.products.last?.id {
                            Task { await loadMorePackaged() }
                        }
                    }
                }
            } header: {
                Text(title).tideLabel()
            }
        }
    }

    // MARK: - Recent / favourites

    @ViewBuilder
    private func savedList(_ rows: [ScannedFood], catalog: FoodCatalog, empty: String, header: String? = nil) -> some View {
        if rows.isEmpty {
            centered {
                FuelEmptyState(icon: selectedTab == .favorites ? "star" : "clock", title: empty)
            }
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
                            .fuelRow()
                        }
                    }
                } header: {
                    if let header {
                        Text(header).tideLabel()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Empty States

    private var searchEmptyState: some View {
        centered {
            FuelEmptyState(
                icon: "magnifyingglass",
                title: "Find any food",
                message: "Search basics like \"chicken breast\" or packaged products by name or brand. Or scan a barcode."
            )
        }
    }

    private var noResultsState: some View {
        centered {
            FuelEmptyState(
                icon: "fork.knife",
                title: "Nothing found",
                message: "Try a shorter name, or scan the barcode."
            ) {
                Button("Scan a barcode") {
                    HapticManager.lightImpact()
                    showScanner = true
                }
                .buttonStyle(.tidePrimary)
            }
        }
    }

    /// Puts an empty-state card in the middle of the space under the picker.
    private func centered(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        nextPage = 2
        canLoadMore = !found.products.isEmpty
    }

    /// Infinite scroll: appends the next packaged page when the last row shows.
    private func loadMorePackaged() async {
        guard canLoadMore, !isLoadingMore, !isLoading, let catalog else {
            return
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoadingMore = true
        let page = await catalog.searchMore(query, page: nextPage)
        isLoadingMore = false
        guard query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        let known = Set((results.yours + results.basics + results.products).map(\.id))
        let fresh = page.filter { !known.contains($0.id) }
        results.products.append(contentsOf: fresh)
        nextPage += 1
        // A page of only already-shown rows isn't the end — OFF ranking can
        // shift between fetches. Only an empty page is.
        canLoadMore = !page.isEmpty
    }
}

// MARK: - Preview

#Preview {
    FoodSearchView()
        .environment(ServiceContainer.mock())
        .modelContainer(for: [ScannedFood.self], inMemory: true)
}
