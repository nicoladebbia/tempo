//
// PantryView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - PantryView

struct PantryView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var showCaptureSheet = false
    @State
    private var showManualAddSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                headerCard
                if !viewModel.pantryState.expiringSoon.isEmpty {
                    expiringSoonSection
                }
                ForEach(PantryStorageLocation.allCases, id: \.rawValue) { location in
                    section(for: location)
                }
                if viewModel.pantryState.items.isEmpty, !viewModel.pantryState.isLoading {
                    emptyState
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.lg)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Pantry")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showManualAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCaptureSheet) {
            if let receiptService = viewModel.receiptService,
               let pantryService = viewModel.pantryService
            {
                ReceiptCaptureView(
                    receiptService: receiptService,
                    pantryService: pantryService
                )
            } else {
                Text("Scan unavailable — open the Pantry tab first.")
                    .padding()
            }
        }
        .sheet(isPresented: $showManualAddSheet) {
            PantryManualAddSheet { rawName, qty, unit, location in
                viewModel.addPantryItem(
                    rawName: rawName,
                    quantity: qty,
                    unit: unit,
                    storageLocation: location
                )
            }
        }
        .refreshable {
            viewModel.reloadPantry()
        }
        .task {
            viewModel.attachPhase7Services(modelContext: modelContext, services: services)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(alignment: .center, spacing: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR PANTRY")
                    .font(.tempoModuleTag)
                    .foregroundStyle(Color.tempoTextTertiary)
                Text("\(viewModel.pantryState.items.count) items tracked")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
            }
            Spacer()
            Button {
                showCaptureSheet = true
            } label: {
                Label("Scan", systemImage: "doc.text.viewfinder")
            }
            .buttonStyle(.tempoPrimary)
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Expiring soon

    private var expiringSoonSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.tempoWarning)
                Text("EXPIRING SOON")
                    .font(.tempoModuleTag)
                    .foregroundStyle(Color.tempoWarning)
            }
            ForEach(viewModel.pantryState.expiringSoon, id: \.id) { item in
                pantryRow(item)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoWarning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Section per location

    @ViewBuilder
    private func section(for location: PantryStorageLocation) -> some View {
        let items = viewModel.pantryState.items.filter { $0.storageLocation == location }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: location.icon)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text(location.displayName.uppercased())
                        .font(.tempoModuleTag)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text("\(items.count)")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Spacer()
                }
                ForEach(items, id: \.id) { item in
                    pantryRow(item)
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
    }

    private func pantryRow(_ item: PantryItem) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                HStack(spacing: 6) {
                    Text("\(formatQuantity(item.quantity))\(item.unit.displayName)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    if let useBy = item.useBy {
                        Text("•")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text("by \(useBy.formatted(date: .abbreviated, time: .omitted))")
                            .font(.tempoCaption1)
                            .foregroundStyle(item.isExpiringSoon ? Color.tempoWarning : Color.tempoTextTertiary)
                    }
                    if item.purchaseSource == .receiptScan {
                        Image(systemName: "doc.text")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
            }
            Spacer()
            Button(role: .destructive) {
                viewModel.archivePantryItem(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoTextTertiary)
            Text("No pantry items yet")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Scan a grocery receipt or add items manually to start.")
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

// MARK: - PantryManualAddSheet

private struct PantryManualAddSheet: View {
    let onAdd: (String, Double, PantryUnit, PantryStorageLocation) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var name = ""
    @State
    private var quantityText = ""
    @State
    private var unit: PantryUnit = .grams
    @State
    private var location: PantryStorageLocation = .pantry

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name (e.g. Chicken Breast)", text: $name)
                    TextField("Quantity", text: $quantityText)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $unit) {
                        ForEach(PantryUnit.allCases, id: \.rawValue) { u in
                            Text(u.displayName).tag(u)
                        }
                    }
                    Picker("Storage", selection: $location) {
                        ForEach(PantryStorageLocation.allCases, id: \.rawValue) { loc in
                            Text(loc.displayName).tag(loc)
                        }
                    }
                }
            }
            .navigationTitle("Add to Pantry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let qty = Double(quantityText) ?? 0
                        guard !name.isEmpty, qty > 0 else {
                            return
                        }
                        onAdd(name, qty, unit, location)
                        dismiss()
                    }
                    .disabled(name.isEmpty || Double(quantityText) ?? 0 <= 0)
                }
            }
        }
    }
}
