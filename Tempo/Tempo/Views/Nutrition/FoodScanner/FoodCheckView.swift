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
    @Environment(\.tideMood)
    private var mood

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
    @State
    private var toast: ToastData?

    enum Tab: String, CaseIterable, Identifiable {
        case history = "History"
        case favorites = "Favourites"

        var id: String {
            rawValue
        }
    }

    var body: some View {
        NavigationStack {
            KitchenList {
                Section {
                    GlassEffectContainer(spacing: Tide.s3) {
                        HStack(spacing: Tide.s3) {
                            actionCard(icon: "barcode.viewfinder", title: "Scan a product", id: "checkScan") {
                                showScanner = true
                            }
                            actionCard(icon: "magnifyingglass", title: "Search", id: "checkSearch") {
                                showSearch = true
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Scan or search for the score, then log it, stock it or list it. Nothing happens until you tap.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }

                Section {
                    KitchenSegmented(options: Tab.allCases, selection: $tab) { $0.rawValue }
                        .accessibilityLabel("List")
                        .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if rows.isEmpty {
                    Section {
                        if tab == .history {
                            KitchenEmpty(
                                systemImage: "clock.arrow.circlepath",
                                title: "Nothing checked yet",
                                message: "Products you scan or open show up here."
                            )
                        } else {
                            KitchenEmpty(
                                systemImage: "star",
                                title: "No favourites yet",
                                message: "Tap the star on a product to keep it here."
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets())
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
                                .listRowBackground(Tide.fill)
                            }
                        }
                        .onDelete { offsets in
                            let doomed = offsets.map { rows[$0] }
                            let snapshots = doomed.map(ScannedFoodSnapshot.init)
                            for row in doomed {
                                catalog.remove(row, in: modelContext)
                            }
                            let context = modelContext
                            let message = snapshots.count == 1
                                ? "\(snapshots[0].name) removed."
                                : "\(FuelWords.count(snapshots.count, "product")) removed."
                            toast = ToastData(message: message, style: .info, actionTitle: "Undo") {
                                for snapshot in snapshots {
                                    snapshot.restore(in: context)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollIndicators(.hidden)
            .navigationTitle("Check Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)
                }
            }
            .tempoToast($toast)
            .sheet(isPresented: $showScanner) {
                UniversalScanView(context: .foodCheck)
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
        .kitchenSheet()
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
            VStack(spacing: Tide.s3) {
                Image(systemName: icon)
                    .font(Tide.title)
                    .foregroundStyle(mood.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
            }
            .frame(maxWidth: .infinity, minHeight: Tide.hit)
            .padding(.vertical, Tide.s6)
            .glassEffect(.regular.tint(Tide.glassCard).interactive(), in: .rect(cornerRadius: Tide.tileRadius))
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
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
