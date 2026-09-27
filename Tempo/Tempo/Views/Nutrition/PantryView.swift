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
    @State
    private var showVoiceSheet = false
    @State
    private var confirmEmpty = false
    @State
    private var showVoiceEditSheet = false
    @State
    private var showBarcodeSheet = false
    @State
    private var showStapleOnboarding = false
    @State
    private var barcodeStaged: [StagedPantryItem] = []
    @State
    private var editingItem: PantryItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                headerCard
                supplementsLink
                receiptsHistoryLink
                if !viewModel.pantryState.expiringSoon.isEmpty {
                    expiringSoonSection
                }
                staplesSection
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Empty pantry", systemImage: "trash", role: .destructive) {
                        confirmEmpty = true
                    }
                    .disabled(viewModel.pantryState.items.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("pantryMoreMenu")
            }
        }
        .confirmationDialog(
            "Empty the whole pantry?",
            isPresented: $confirmEmpty,
            titleVisibility: .visible
        ) {
            Button("Remove all \(viewModel.pantryState.items.count) items", role: .destructive) {
                viewModel.emptyPantry()
                HapticManager.success()
            }
        } message: {
            Text("Every item comes off your pantry. Prices you paid are kept.")
        }
        .sheet(isPresented: $showCaptureSheet) {
            if let receiptService = viewModel.receiptService,
               let pantryService = viewModel.pantryService
            {
                ReceiptCaptureView(
                    receiptService: receiptService,
                    pantryService: pantryService,
                    onIngested: { viewModel.reapplyPantryToGrocery() }
                )
            } else {
                Text("Scan unavailable — open the Pantry tab first.")
                    .padding()
            }
        }
        .sheet(isPresented: $showManualAddSheet) {
            PantryManualAddSheet(initialStaged: barcodeStaged) { stagedItems in
                for item in stagedItems {
                    viewModel.addPantryItem(
                        rawName: item.name,
                        quantity: item.quantity,
                        unit: item.unit,
                        storageLocation: item.location,
                        totalPaidUSD: item.totalPaidUSD,
                        brand: item.brand
                    )
                }
                barcodeStaged = []
            }
        }
        .fullScreenCover(isPresented: $showVoiceSheet) {
            VoicePantryView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showVoiceEditSheet) {
            PantryVoiceEditView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showBarcodeSheet) {
            PantryBarcodeScanView { scannedItems in
                barcodeStaged = scannedItems
                showBarcodeSheet = false
                showManualAddSheet = true
            }
        }
        .sheet(item: $editingItem) { item in
            PantryItemEditSheet(item: item, viewModel: viewModel)
        }
        .sheet(isPresented: $showStapleOnboarding) {
            PantryStapleOnboardingSheet { picks in
                viewModel.seedSelectedStaples(picks)
            }
        }
        .refreshable {
            viewModel.reloadPantry()
        }
        .task {
            viewModel.attachPhase7Services(modelContext: modelContext, services: services)
        }
        .onChange(of: viewModel.stapleState.shouldOfferOnboarding) { _, shouldOffer in
            if shouldOffer {
                showStapleOnboarding = true
            }
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
            Menu {
                Button {
                    showVoiceSheet = true
                } label: {
                    Label("Add by voice", systemImage: "mic.fill")
                }
                Button {
                    showVoiceEditSheet = true
                } label: {
                    Label("Edit by voice", systemImage: "waveform")
                }
                Button {
                    showBarcodeSheet = true
                } label: {
                    Label("Scan barcode", systemImage: "barcode.viewfinder")
                }
            } label: {
                Image(systemName: "mic.fill")
            }
            .buttonStyle(.tempoSecondary)
            .accessibilityLabel("Pantry voice tools")
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

    /// Link to the supplement shelf — the sibling "what I own" inventory. The
    /// meal-plan AI reads it to decide daily take/skip.
    private var supplementsLink: some View {
        NavigationLink {
            SupplementsView()
        } label: {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: "pills.fill")
                    .foregroundStyle(Color.tempoSignal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Supplements")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("Your shelf — the plan decides daily take/skip")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Link to receipt history — status, retry, delete for every scanned receipt.
    private var receiptsHistoryLink: some View {
        NavigationLink {
            ReceiptsHistoryView(viewModel: viewModel)
        } label: {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: "receipt")
                    .foregroundStyle(Color.tempoSignal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receipts")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("\(viewModel.receiptState.receipts.count) scanned — status, retry, delete")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Staples

    @ViewBuilder
    private var staplesSection: some View {
        if !viewModel.stapleState.staples.isEmpty {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: "leaf")
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text("STAPLES")
                        .font(.tempoModuleTag)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Text("\(viewModel.stapleState.staples.count)")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Spacer()
                }
                ForEach(viewModel.stapleState.staples, id: \.id) { staple in
                    stapleRow(staple)
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
    }

    private func stapleRow(_ staple: PantryStaple) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Text(staple.displayName)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Button {
                viewModel.cycleStapleStatus(staple)
                HapticManager.lightImpact()
            } label: {
                Text(staple.status.label.uppercased())
                    .font(.tempoCaption2.weight(.semibold))
                    .foregroundStyle(stapleStatusColor(staple.status))
                    .padding(.horizontal, TempoSpacing.sm)
                    .padding(.vertical, 4)
                    .background(stapleStatusColor(staple.status).opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(staple.displayName): \(staple.status.label). Tap to cycle.")
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.deleteStaple(staple)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func stapleStatusColor(_ status: StapleStatus) -> Color {
        switch status {
        case .have: Color.tempoSuccess
        case .runningLow: Color.tempoWarning
        case .out: Color.tempoError
        }
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
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                    // Brand distinguishes two rows of the same food (e.g. two
                    // butters of different brands kept as separate stock).
                    if !item.brand.isEmpty {
                        Text(item.brand)
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.tempoSurfaceCard)
                            .clipShape(Capsule())
                    }
                    if item.isDepleted {
                        Text("USED UP")
                            .font(.tempoCaption2.weight(.semibold))
                            .foregroundStyle(Color.tempoTextTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.tempoTextTertiary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
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
        .contentShape(Rectangle())
        .onTapGesture {
            editingItem = item
        }
        .swipeActions(edge: .trailing) {
            Button {
                viewModel.updatePantryItem(item, quantity: 0)
            } label: {
                Label("Used up", systemImage: "checkmark.circle")
            }
            .tint(Color.tempoTextTertiary)
            if item.storageLocation != .freezer {
                Button {
                    viewModel.updatePantryItem(item, storageLocation: .freezer)
                } label: {
                    Label("Freezer", systemImage: "snowflake")
                }
                .tint(Color.tempoSignal)
            }
        }
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
    /// Brand, when known — prefilled by barcode scanning, or typed manually.
    var brand: String = ""
}

// MARK: - PantryManualAddSheet

/// Not private: `PantryBarcodeScanView` reuses this exact sheet (via
/// `initialStaged`) so scanned products go through the SAME confirm/edit/
/// save flow as a manual add — one save path, two entry points.
struct PantryManualAddSheet: View {
    /// Called once with every staged item when the user taps Save.
    let onAdd: ([StagedPantryItem]) -> Void

    @Environment(\.dismiss)
    private var dismiss

    // Current form row.
    @State private var name = ""
    @State private var brand = ""
    @State private var quantityText = ""
    @State private var unit: PantryUnit = .grams
    @State private var location: PantryStorageLocation = .pantry
    /// Optional total USD paid — locks this purchase's price into history.
    @State private var priceText = ""
    @State private var transcriber = VoiceTranscriber()

    /// Staging list — items the user has queued but not yet committed.
    /// Pre-populated by barcode scanning (one or more products scanned in a
    /// row before the user ever sees this sheet); starts empty for manual add.
    @State private var staged: [StagedPantryItem]

    init(initialStaged: [StagedPantryItem] = [], onAdd: @escaping ([StagedPantryItem]) -> Void) {
        self.onAdd = onAdd
        _staged = State(initialValue: initialStaged)
    }

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
            TextField("Brand (optional)", text: $brand)
                .textInputAutocapitalization(.words)
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
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.tempoBody)
                    if !item.brand.isEmpty {
                        Text(item.brand)
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
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
        guard canAddCurrent, let qty = Double(quantityText) else {
            return
        }
        staged.append(StagedPantryItem(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: qty,
            unit: unit,
            location: location,
            totalPaidUSD: Double(priceText.trimmingCharacters(in: .whitespaces)),
            brand: brand.trimmingCharacters(in: .whitespaces)
        ))
        HapticManager.lightImpact()
        // Clear the form for the next row. Keep unit + location sticky so
        // adding a batch of "grams / pantry" items doesn't re-pick every
        // time. Stop the transcriber so the next row starts clean.
        name = ""
        brand = ""
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
        guard !staged.isEmpty else {
            return
        }
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
