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
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var showHomeSetting = false
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
    private var showStaples = false
    @State
    private var staplesDetent: PresentationDetent = .large
    @State
    private var barcodeStaged: [StagedPantryItem] = []
    @State
    private var editingItem: PantryItem?
    @State
    private var cycles = 0

    /// Something is presented over the page: its shaders stop.
    private var isCovered: Bool {
        showHomeSetting || showCaptureSheet || showManualAddSheet || showVoiceSheet || showVoiceEditSheet
            || showBarcodeSheet || showStaples || editingItem != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s5) {
                hero
                // In the flow of the page, never pinned over the rows it would hide.
                if showsStaplesPeek {
                    if !showStaples {
                        StaplesPeekCard(remaining: viewModel.unansweredStapleCount) {
                            staplesDetent = .large
                            showStaples = true
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                } else {
                    staplesChip
                }
                if !viewModel.pantryState.expiringSoon.isEmpty {
                    expiringSoonSection
                }
                staplesSection
                ForEach(PantryStorageLocation.allCases, id: \.rawValue) { location in
                    section(for: location)
                }
                if viewModel.pantryState.items.isEmpty {
                    if viewModel.pantryState.isLoading {
                        LoadingStateView(style: .list)
                    } else {
                        emptyState
                    }
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .tidePage()
        .tideCovered(isCovered)
        .animation(Tide.snap, value: showsStaplesPeek)
        .sensoryFeedback(.selection, trigger: cycles)
        .toolbar {
            // Visible home control (it used to hide in the ⋯ menu only).
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showHomeSetting = true
                } label: {
                    Image(systemName: HomeLocationStore().home == nil ? "house" : "house.fill")
                }
                .accessibilityLabel(HomeLocationStore().home == nil ? "Set home" : "Home location")
                .accessibilityIdentifier("pantryHomeButton")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add item", systemImage: "plus") {
                        showManualAddSheet = true
                    }
                    .accessibilityIdentifier("pantryAddItem")
                    Button("Staples", systemImage: "leaf") {
                        viewModel.applyStapleEvent(.reopen)
                        staplesDetent = .large
                        showStaples = true
                    }
                    Button("Set home", systemImage: "house") {
                        showHomeSetting = true
                    }
                    .accessibilityIdentifier("pantrySetHome")
                    Button("Empty pantry", systemImage: "trash", role: .destructive) {
                        confirmEmpty = true
                    }
                    .disabled(viewModel.pantryState.items.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("pantryMoreMenu")
            }
        }
        .sheet(isPresented: $showHomeSetting) {
            HomeLocationSettingView()
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
                UniversalScanView(context: .pantryReceipt(
                    receiptService: receiptService,
                    pantryService: pantryService,
                    onIngested: { viewModel.reapplyPantryToGrocery() }
                ))
            } else {
                Text("Scan unavailable — open the Pantry tab first.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .padding(Tide.s4)
                    .kitchenSheet()
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
            UniversalScanView(context: .pantryBarcode { scannedItems in
                barcodeStaged = scannedItems
                showBarcodeSheet = false
                showManualAddSheet = true
            })
        }
        .sheet(item: $editingItem) { item in
            PantryItemEditSheet(item: item, viewModel: viewModel)
        }
        .sheet(isPresented: $showStaples) {
            StaplesSheet(viewModel: viewModel, detent: $staplesDetent)
                .presentationDetents([.height(StaplesSheet.peekHeight), .large], selection: $staplesDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(StaplesSheet.peekHeight)))
        }
        .refreshable {
            viewModel.reloadPantry()
        }
        .task {
            viewModel.attachPhase7Services(modelContext: modelContext, services: services)
        }
        .onAppear {
            viewModel.loadStaplePromptState()
        }
    }

    private var showsStaplesPeek: Bool {
        viewModel.stapleState.prompt.showsPeekCard
    }

    /// Always-findable entry once the peek card is gone (skipped / done).
    private var staplesChip: some View {
        TideChip(title: "Staples · \(viewModel.stapleState.staples.count)", systemImage: "leaf") {
            viewModel.applyStapleEvent(.reopen)
            staplesDetent = .large
            showStaples = true
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("staplesChip")
    }

    // MARK: - Hero

    /// What you have, what needs using, and the two ways to add more.
    private var hero: some View {
        let state = viewModel.pantryState
        let soon = state.expiringSoon.count
        let staples = viewModel.stapleState.staples.count
        return VStack(alignment: .leading, spacing: Tide.s4) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s4))
            layout {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("In your pantry").tideLabel()
                    TideNumber("\(state.items.count)", size: Tide.numeralL, relativeTo: .largeTitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if soon > 0 || staples > 0 {
                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: Tide.s2) {
                        if soon > 0 {
                            heroFigure("Use soon", value: soon, color: Tide.Kitchen.warn)
                        }
                        if staples > 0 {
                            heroFigure("Staples", value: staples, color: Tide.text)
                        }
                    }
                }
            }
            if state.items.count > 0 {
                KitchenShelfBar(parts: [
                    .init(id: "stocked", value: Double(max(state.items.count - soon, 0)), color: mood.accent),
                    .init(id: "soon", value: Double(soon), color: Tide.Kitchen.warn),
                ])
            }
            HStack(spacing: Tide.s3) {
                Button {
                    showCaptureSheet = true
                } label: {
                    Label("Scan", systemImage: "doc.text.viewfinder")
                }
                .buttonStyle(.tidePrimary)
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
                        .frame(minHeight: Tide.hit + Tide.s2)
                }
                .buttonStyle(.tideGlass)
                .fixedSize()
                .accessibilityLabel("Pantry voice tools")
            }
        }
        .tideCard()
    }

    /// A small figure beside the big one: a label and a count.
    private func heroFigure(_ label: String, value: Int, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
            Text(label).tideLabel()
            TideNumber("\(value)", size: Tide.numeralS, relativeTo: .headline, color: color)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Staples

    @ViewBuilder
    private var staplesSection: some View {
        if !viewModel.stapleState.staples.isEmpty {
            KitchenGroup(
                title: "Staples",
                systemImage: "leaf",
                trailing: "\(viewModel.stapleState.staples.count)"
            ) {
                ForEach(viewModel.stapleState.staples, id: \.id) { staple in
                    stapleRow(staple)
                }
            }
        }
    }

    private func stapleRow(_ staple: PantryStaple) -> some View {
        HStack(spacing: Tide.s3) {
            Text(staple.displayName)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
            Spacer(minLength: Tide.s2)
            Button {
                viewModel.cycleStapleStatus(staple)
                cycles += 1
            } label: {
                KitchenTag(text: staple.status.label, tint: stapleStatusColor(staple.status))
                    .frame(minHeight: Tide.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(staple.displayName): \(staple.status.label). Tap to cycle.")
        }
        // Long press: the "Remove" action that used to sit on a swipe (a swipe
        // only works inside a List, so it never showed).
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteStaple(staple)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func stapleStatusColor(_ status: StapleStatus) -> Color {
        switch status {
        case .have: Tide.Kitchen.good
        case .runningLow: Tide.Kitchen.warn
        case .out: Tide.danger
        }
    }

    // MARK: - Expiring soon

    private var expiringSoonSection: some View {
        KitchenGroup(
            title: "Expiring soon",
            systemImage: "exclamationmark.triangle.fill",
            tint: Tide.Kitchen.warn
        ) {
            ForEach(viewModel.pantryState.expiringSoon, id: \.id) { item in
                pantryRow(item)
            }
        }
    }

    // MARK: - Section per location

    @ViewBuilder
    private func section(for location: PantryStorageLocation) -> some View {
        let items = viewModel.pantryState.items.filter { $0.storageLocation == location }
        if !items.isEmpty {
            KitchenGroup(
                title: location.displayName,
                systemImage: location.icon,
                trailing: "\(items.count)"
            ) {
                ForEach(items, id: \.id) { item in
                    pantryRow(item)
                }
            }
        }
    }

    private func pantryRow(_ item: PantryItem) -> some View {
        HStack(spacing: Tide.s2) {
            Button {
                editingItem = item
            } label: {
                HStack(alignment: .center, spacing: Tide.s3) {
                    // The photo is decoration: at the accessibility sizes it gives its width to the words.
                    if !typeSize.isAccessibilitySize {
                        ProductImageView(
                            url: nil,
                            fallbackIcon: ReceiptProductPhoto.categoryIcon(forCanonicalName: item.canonicalName, isNonFood: false),
                            size: Tide.Kitchen.tile
                        )
                        .opacity(item.isDepleted ? 0.5 : 1)
                    }
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
                        : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s2))
                    layout {
                        VStack(alignment: .leading, spacing: Tide.s1) {
                            Text(item.displayName)
                                .font(Tide.headline)
                                .foregroundStyle(item.isDepleted ? Tide.text3 : Tide.text)
                                .lineLimit(2)
                            // Brand distinguishes two rows of the same food (e.g. two
                            // butters of different brands kept as separate stock).
                            if !item.brand.isEmpty || item.isDepleted {
                                HStack(spacing: Tide.s1) {
                                    if !item.brand.isEmpty {
                                        KitchenTag(text: item.brand)
                                    }
                                    if item.isDepleted {
                                        KitchenTag(text: "Used up", tint: Tide.text3)
                                    }
                                }
                            }
                            detailLine(item)
                        }
                        if !typeSize.isAccessibilitySize {
                            Spacer(minLength: Tide.s2)
                        }
                        TideNumber(
                            PantryQuantityFormatter.text(
                                quantity: item.quantity, unit: item.unit,
                                canonicalName: item.canonicalName, purchased: item.weighsPurchaseUnit
                            ),
                            size: Tide.numeralS, relativeTo: .headline, weight: .semibold,
                            color: item.isDepleted ? Tide.text3 : Tide.text
                        )
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit")
            Button(role: .destructive) {
                viewModel.archivePantryItem(item)
            } label: {
                Image(systemName: "trash")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text3)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Archive \(item.canonicalName)")
        }
        // Long press: the "Used up" and "Freezer" actions that used to sit on a
        // swipe (a swipe only works inside a List, so it never showed).
        .overlay(alignment: .leading) {
            freshnessStripe(item)
        }
        .contextMenu {
            Button {
                viewModel.updatePantryItem(item, quantity: 0)
            } label: {
                Label("Used up", systemImage: "checkmark.circle")
            }
            if item.storageLocation != .freezer {
                Button {
                    viewModel.updatePantryItem(item, storageLocation: .freezer)
                } label: {
                    Label("Freezer", systemImage: "snowflake")
                }
            }
        }
    }

    /// A thin light on the card's edge: red once the use-by date has passed,
    /// amber when it is close, green while it is fine. Nothing without a date.
    @ViewBuilder
    private func freshnessStripe(_ item: PantryItem) -> some View {
        if item.useBy != nil, !item.isDepleted {
            let color = item.isExpired ? Tide.danger : (item.isExpiringSoon ? Tide.Kitchen.warn : Tide.Kitchen.good)
            Capsule()
                .fill(color)
                .frame(width: Tide.Kitchen.stripe)
                .padding(.vertical, Tide.s1)
                .offset(x: -Tide.s3)
                .accessibilityHidden(true)
        }
    }

    /// Use-by date, receipt mark and last price under the name.
    @ViewBuilder
    private func detailLine(_ item: PantryItem) -> some View {
        let paid = viewModel.pantryState.latestPriceByFood[item.canonicalName] ?? 0
        if item.useBy != nil || item.purchaseSource == .receiptScan || paid > 0 {
            HStack(spacing: Tide.s2) {
                if let useBy = item.useBy {
                    Text("by \(useBy.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(item.isExpiringSoon ? Tide.Kitchen.warn : Tide.text2)
                }
                if item.purchaseSource == .receiptScan {
                    Image(systemName: "doc.text")
                        .accessibilityLabel("From a receipt")
                }
                if paid > 0 {
                    Text(String(format: "$%.2f", paid))
                }
            }
            .font(Tide.caption)
            .foregroundStyle(Tide.text2)
        }
    }

    private var emptyState: some View {
        KitchenEmpty(
            systemImage: "tray",
            title: "No pantry items yet",
            message: "Scan a grocery receipt or add items manually to start.",
            actionTitle: "Add an item"
        ) {
            showManualAddSheet = true
        }
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
    @Environment(\.tideMood)
    private var mood

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
            ScrollView {
                VStack(spacing: Tide.s4) {
                    currentRowSection
                    if !staged.isEmpty {
                        stagedSection
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
                .animation(Tide.snap, value: staged.count)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Saving is the one thing left to do, so it sits under the thumb.
            .kitchenBottomBar {
                Button(saveButtonTitle) {
                    commitAndClose()
                }
                .buttonStyle(.kitchenBar)
                .disabled(staged.isEmpty && !canAddCurrent)
                .accessibilityIdentifier("pantryAddSave")
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
        .kitchenSheet()
        .sensoryFeedback(.impact(weight: .light), trigger: staged.count)
    }

    // MARK: - Sections

    private var currentRowSection: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            Text("New item").tideLabel()
            VStack(alignment: .leading, spacing: Tide.s2) {
                HStack(spacing: Tide.s2) {
                    TextField("Name (e.g. Chicken Breast)", text: $name)
                        .submitLabel(.next)
                        .kitchenField()
                    micButton
                }
                if transcriber.isListening {
                    Text("Listening… speak the item name.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                } else if let error = transcriber.error {
                    Text(error)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                }
                TextField("Brand (optional)", text: $brand)
                    .textInputAutocapitalization(.words)
                    .kitchenField()
            }
            KitchenPair {
                KitchenNumberField(label: "Quantity", placeholder: "Qty", text: $quantityText)
            } second: {
                KitchenNumberField(label: "Price paid", unit: "USD", placeholder: "Optional", text: $priceText)
            }
            HStack {
                Text("Unit")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                Spacer(minLength: Tide.s2)
                Picker("Unit", selection: $unit) {
                    ForEach(PantryUnit.allCases, id: \.rawValue) { u in
                        Text(u.displayName).tag(u)
                    }
                }
                .pickerStyle(.menu)
                .tint(mood.accent)
            }
            .frame(minHeight: Tide.hit)
            KitchenSegmented(options: Array(PantryStorageLocation.allCases), selection: $location) { $0.displayName }
                .accessibilityLabel("Storage")
            Button {
                stageCurrentRow()
            } label: {
                Label("Add to list", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tideGlass)
            .disabled(!canAddCurrent)
        }
        .tideCard()
    }

    private var stagedSection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Staged (\(staged.count))").tideLabel()
            VStack(spacing: 0) {
                ForEach(Array(staged.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle().fill(Tide.hairline).frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: Tide.s2) {
                        stagedRow(item)
                        Button {
                            withAnimation(Tide.snap) {
                                staged.removeAll { $0.id == item.id }
                            }
                            HapticManager.lightImpact()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Tide.text3)
                                .frame(width: Tide.hit, height: Tide.hit)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(item.name)")
                    }
                    .padding(.vertical, Tide.s1)
                }
            }
            .tideCard(padding: Tide.s4)
        }
    }

    private func stagedRow(_ item: StagedPantryItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Tide.hair) {
                HStack(spacing: Tide.s2) {
                    Text(item.name)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                    if !item.brand.isEmpty {
                        KitchenTag(text: item.brand)
                    }
                }
                Text("\(Self.formatQuantity(item.quantity)) \(item.unit.displayName) · \(item.location.displayName)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            Spacer()
            if let paid = item.totalPaidUSD, paid > 0 {
                TideNumber(
                    String(format: "$%.2f", paid), size: Tide.numeralS, relativeTo: .body,
                    weight: .semibold
                )
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
        PantryQuantityFormatter.number(value)
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
                .font(Tide.bodyStrong)
                .foregroundStyle(transcriber.isListening ? Tide.ink : Tide.text2)
                .frame(width: Tide.hit, height: Tide.hit)
                .background(transcriber.isListening ? mood.accent : Color.clear, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(transcriber.isListening ? "Stop listening" : "Start voice input")
    }
}
