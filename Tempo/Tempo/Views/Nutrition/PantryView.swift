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
            PantryManualAddSheet { stagedItems in
                for item in stagedItems {
                    viewModel.addPantryItem(
                        rawName: item.name,
                        quantity: item.quantity,
                        unit: item.unit,
                        storageLocation: item.location,
                        totalPaidUSD: item.totalPaidUSD
                    )
                }
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
                    if let paid = viewModel.pantryState.latestPriceByFood[item.canonicalName], paid > 0 {
                        Text("•")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text(String(format: "$%.2f", paid))
                            .font(.tempoCaption1)
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
            .accessibilityLabel("Archive \(item.canonicalName)")
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

// MARK: - StagedPantryItem

/// In-flight pantry row inside `PantryManualAddSheet`. Stays a value type
/// so the staging list can render in a ForEach without SwiftData reach;
/// the parent view's batch callback materialises these into real
/// `PantryItem` rows on Save.
struct StagedPantryItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var quantity: Double
    var unit: PantryUnit
    var location: PantryStorageLocation
    /// Total USD paid for this purchase, optional. When set, the parent
    /// materialises a PantryPriceEntry so the food's price history is tracked
    /// even though manual adds have no receipt.
    var totalPaidUSD: Double?
}

// MARK: - PantryManualAddSheet

private struct PantryManualAddSheet: View {
    /// Called once with every staged item when the user taps Save.
    let onAdd: ([StagedPantryItem]) -> Void

    @Environment(\.dismiss)
    private var dismiss

    // Current form row.
    @State private var name = ""
    @State private var quantityText = ""
    @State private var unit: PantryUnit = .grams
    @State private var location: PantryStorageLocation = .pantry
    /// Optional total USD paid — locks this purchase's price into history.
    @State private var priceText = ""
    @State private var transcriber = VoiceTranscriber()

    // Staging list — items the user has queued but not yet committed.
    @State private var staged: [StagedPantryItem] = []

    private var canAddCurrent: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Double(quantityText) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                currentRowSection
                if !staged.isEmpty {
                    stagedSection
                }
            }
            .navigationTitle(stagedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        transcriber.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saveButtonTitle) {
                        commitAndClose()
                    }
                    .disabled(staged.isEmpty && !canAddCurrent)
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: transcriber.transcribedText) { _, newText in
                if transcriber.isListening, !newText.isEmpty {
                    name = newText
                }
            }
            .onDisappear {
                transcriber.stop()
            }
        }
    }

    // MARK: - Sections

    private var currentRowSection: some View {
        Section("New item") {
            HStack(spacing: 8) {
                TextField("Name (e.g. Chicken Breast)", text: $name)
                    .submitLabel(.next)
                micButton
            }
            if transcriber.isListening {
                Text("Listening… speak the item name.")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            } else if let error = transcriber.error {
                Text(error)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoError)
            }
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
            TextField("Price paid (optional, USD)", text: $priceText)
                .keyboardType(.decimalPad)
            Button {
                stageCurrentRow()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add to list")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(canAddCurrent ? Color.tempoAmber : Color.tempoTextTertiary)
            }
            .disabled(!canAddCurrent)
        }
    }

    private var stagedSection: some View {
        Section("Staged (\(staged.count))") {
            ForEach(staged) { item in
                stagedRow(item)
            }
            .onDelete { offsets in
                staged.remove(atOffsets: offsets)
                HapticManager.lightImpact()
            }
        }
    }

    private func stagedRow(_ item: StagedPantryItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.tempoBody)
                Text("\(Self.formatQuantity(item.quantity)) \(item.unit.displayName) · \(item.location.displayName)")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            Spacer()
            if let paid = item.totalPaidUSD, paid > 0 {
                Text(String(format: "$%.2f", paid))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
    }

    // MARK: - Computed labels

    private var stagedTitle: String {
        staged.isEmpty ? "Add to Pantry" : "Add to Pantry · \(staged.count)"
    }

    private var saveButtonTitle: String {
        let pending = canAddCurrent ? staged.count + 1 : staged.count
        return pending <= 1 ? "Save" : "Save \(pending)"
    }

    // MARK: - Actions

    private func stageCurrentRow() {
        guard canAddCurrent, let qty = Double(quantityText) else { return }
        staged.append(StagedPantryItem(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: qty,
            unit: unit,
            location: location,
            totalPaidUSD: Double(priceText.trimmingCharacters(in: .whitespaces))
        ))
        HapticManager.lightImpact()
        // Clear the form for the next row. Keep unit + location sticky so
        // adding a batch of "grams / pantry" items doesn't re-pick every
        // time. Stop the transcriber so the next row starts clean.
        name = ""
        quantityText = ""
        priceText = ""
        transcriber.stop()
    }

    private func commitAndClose() {
        // If the user filled the form but didn't tap "Add to list", treat
        // Save as an implicit stage-then-commit.
        if canAddCurrent {
            stageCurrentRow()
        }
        guard !staged.isEmpty else { return }
        transcriber.stop()
        onAdd(staged)
        dismiss()
    }

    private static func formatQuantity(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.2f", value)
    }

    private var micButton: some View {
        Button {
            if transcriber.isListening {
                transcriber.stop()
            } else {
                Task { await transcriber.start() }
            }
            HapticManager.lightImpact()
        } label: {
            Image(systemName: transcriber.isListening ? "mic.fill" : "mic")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(transcriber.isListening ? Color.tempoSignal : Color.tempoTextSecondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(transcriber.isListening ? Color.tempoSignal.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(transcriber.isListening ? "Stop listening" : "Start voice input")
    }
}
