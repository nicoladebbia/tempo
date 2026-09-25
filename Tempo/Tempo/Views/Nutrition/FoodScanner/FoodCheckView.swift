//
// FoodCheckView.swift
// Tempo
//
// Scan-to-check hub (Nutrition → Check): scan or search any product to see
// its Tempo score without logging anything, plus everything you've checked
// before and your favourites.
//

import SwiftData
import SwiftUI

// MARK: - FoodCheckView

struct FoodCheckView: View {
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    @Query(sort: \ScannedFood.lastViewedAt, order: .reverse)
    private var saved: [ScannedFood]

    @State
    private var tab: Tab = .history
    @State
    private var showScanner = false
    @State
    private var showSearch = false
    @State
    private var catalog: FoodCatalog?

    enum Tab: String, CaseIterable, Identifiable {
        case history = "History"
        case favorites = "Favourites"

        var id: String {
            rawValue
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: TempoSpacing.md) {
                        actionCard(icon: "barcode.viewfinder", title: "Scan a product", id: "checkScan") {
                            showScanner = true
                        }
                        actionCard(icon: "magnifyingglass", title: "Search", id: "checkSearch") {
                            showSearch = true
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Nothing gets logged here — just the score: nutrition, additives and what it means for you today.")
                        .font(.tempoCaption1)
                }

                Section {
                    Picker("List", selection: $tab) {
                        ForEach(Tab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if rows.isEmpty {
                    Text(tab == .history ? "Products you scan or open show up here." : "Tap the star on a product to keep it here.")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .listRowBackground(Color.clear)
                } else if let catalog {
                    Section {
                        ForEach(rows) { row in
                            if let product = row.product {
                                NavigationLink {
                                    FoodProductView(product: product, catalog: catalog)
                                } label: {
                                    FoodProductRow(product: product, photo: row.photoData, subtitle: subtitle(row))
                                }
                                .listRowBackground(Color.tempoSurfaceCard)
                            }
                        }
                        .onDelete { offsets in
                            let doomed = offsets.map { rows[$0] }
                            for row in doomed {
                                catalog.remove(row, in: modelContext)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Check Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView()
            }
            .sheet(isPresented: $showSearch) {
                FoodSearchView()
            }
            .onAppear {
                if catalog == nil {
                    catalog = FoodCatalog(services: services)
                }
            }
        }
    }

    private var rows: [ScannedFood] {
        switch tab {
        case .history: saved
        case .favorites: saved.filter(\.isFavorite).sorted { $0.name < $1.name }
        }
    }

    private func subtitle(_ row: ScannedFood) -> String {
        var parts: [String] = []
        if let brand = row.brand, !brand.isEmpty {
            parts.append(brand)
        }
        if row.isUserAdded {
            parts.append("Added by you")
        }
        parts.append(row.lastViewedAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }

    private func actionCard(icon: String, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.lightImpact()
            action()
        } label: {
            VStack(spacing: TempoSpacing.sm) {
                Image(systemName: icon)
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoSignal)
                Text(title)
                    .font(.tempoBodyBold)
                    .foregroundStyle(Color.tempoTextPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TempoSpacing.xl)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

#Preview {
    FoodCheckView()
        .environment(ServiceContainer.mock())
        .modelContainer(for: [ScannedFood.self], inMemory: true)
}
