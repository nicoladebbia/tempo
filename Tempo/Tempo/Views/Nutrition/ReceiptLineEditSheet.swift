//
// ReceiptLineEditSheet.swift
// Tempo
//
// Edit one receipt line: name, qty, unit, price, storage, expiry, and
// "Is it this one?" product candidates with photos. Picking a product (or
// saving) teaches the store-name → product mapping through the caller's
// `confirmAlias`.
//

import SwiftUI

// MARK: - Result

enum ReceiptLineProductChoice {
    case unchanged
    case keptAsTyped
    case picked(ReceiptProductPickerCandidate)
}

struct ReceiptLineEditResult {
    var name: String
    var quantity: Double
    var unit: ReceiptLineUnit
    var price: Double
    var storage: PantryStorageLocation
    var useBy: Date?
    var included: Bool
    var product: ReceiptLineProductChoice
}

// MARK: - ReceiptLineEditSheet

struct ReceiptLineEditSheet: View {
    let line: ReceiptLineItem
    let storeChain: String?
    let onSave: (ReceiptLineEditResult) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood
    @State
    private var name: String
    @State
    private var quantityText: String
    @State
    private var priceText: String
    @State
    private var unit: ReceiptLineUnit
    @State
    private var storage: PantryStorageLocation
    @State
    private var hasExpiry: Bool
    @State
    private var useBy: Date
    @State
    private var included: Bool
    @State
    private var product: ReceiptLineProductChoice = .unchanged
    @State
    private var candidates: [(product: FoodProduct, score: Double)] = []
    @State
    private var isLoadingCandidates = false
    @State
    private var showFullPicker = false

    private let provider: any FoodProductProviding = OpenFoodFactsClient()

    init(
        line: ReceiptLineItem,
        edits: ReceiptLineEdits,
        defaultStorage: PantryStorageLocation,
        storeChain: String?,
        onSave: @escaping (ReceiptLineEditResult) -> Void
    ) {
        self.line = line
        self.storeChain = storeChain
        self.onSave = onSave
        _name = State(initialValue: line.displayName.isEmpty ? line.rawText : line.displayName)
        _quantityText = State(initialValue: ReceiptQuantityParser.format(line.quantity))
        _priceText = State(initialValue: ReceiptQuantityParser.format(line.totalPrice))
        _unit = State(initialValue: line.unit)
        let initial = edits.storage ?? defaultStorage
        _storage = State(initialValue: initial == .cupboard ? .pantry : initial)
        _hasExpiry = State(initialValue: edits.useBy != nil)
        _useBy = State(initialValue: edits.useBy ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        _included = State(initialValue: edits.included ?? !(line.isNonFood || line.isFee))
    }

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tide.s4) {
                    identityCard
                    candidatesCard
                    amountCard
                    locationCard
                    includeCard
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // The one action under the thumb.
            .kitchenBottomBar {
                Button("Save") { save() }
                    .buttonStyle(.tidePrimary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("receiptLineSave")
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showFullPicker) {
                ReceiptProductPickerView(line: line, storeChain: storeChain) { candidate, keptAsTyped in
                    if keptAsTyped {
                        product = .keptAsTyped
                    } else {
                        product = .picked(candidate)
                        name = candidate.readableName
                    }
                    showFullPicker = false
                }
            }
            .task { await loadCandidates() }
        }
        .kitchenSheet()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Cards

    /// What this line is: its picture, the name you can fix, and what the receipt said.
    private var identityCard: some View {
        HStack(alignment: .center, spacing: Tide.s4) {
            ProductImageView(
                url: ReceiptProductPhoto.url(
                    imageURL: line.imageURL,
                    barcode: line.barcode,
                    matchConfidence: line.matchConfidence,
                    userPicked: pickedCandidate != nil
                ),
                fallbackIcon: ReceiptProductPhoto.categoryIcon(
                    forCanonicalName: line.canonicalFoodName,
                    isNonFood: line.isNonFood || line.isFee
                ),
                size: Tide.Kitchen.tile + Tide.s6
            )
            VStack(alignment: .leading, spacing: Tide.s1) {
                TextField("Item name", text: $name, axis: .vertical)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .lineLimit(1 ... 3)
                    .accessibilityIdentifier("receiptLineName")
                Text("On receipt: \(line.rawText)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tideCard()
    }

    @ViewBuilder
    private var candidatesCard: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s3) {
                Text("Is it this one?").tideLabel()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tide.s3) {
                        ForEach(Array(candidates.enumerated()), id: \.offset) { _, entry in
                            candidateCard(entry.product, score: entry.score)
                        }
                    }
                    .padding(.vertical, Tide.s1)
                }
                Button("Find another product") { showFullPicker = true }
                    .buttonStyle(.tideGlass)
            }
            .tideCard()
        } else if isLoadingCandidates {
            VStack(alignment: .leading, spacing: Tide.s3) {
                Text("Is it this one?").tideLabel()
                HStack(spacing: Tide.s3) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                            .fill(Tide.fill)
                            .frame(width: Tide.Kitchen.suggestion, height: Tide.Kitchen.suggestion)
                    }
                }
                .shimmer()
                .accessibilityLabel("Looking for matching products")
            }
            .tideCard()
        } else {
            Button("Find exact product") { showFullPicker = true }
                .buttonStyle(.tideGlass)
                .frame(maxWidth: .infinity)
        }
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Amount").tideLabel()
            let columns = [GridItem(.flexible(), spacing: Tide.s3), GridItem(.flexible(), spacing: Tide.s3)]
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : columns, spacing: Tide.s3) {
                KitchenNumberField(label: "Quantity", placeholder: "Qty", text: $quantityText)
                KitchenNumberField(label: "Price", unit: "$", placeholder: "Price", text: $priceText)
            }
            HStack {
                Text("Unit")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                Spacer(minLength: Tide.s2)
                Picker("Unit", selection: $unit) {
                    ForEach(ReceiptLineUnit.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .tint(mood.accent)
            }
            .frame(minHeight: Tide.hit)
        }
        .tideCard()
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Where does it go?").tideLabel()
            KitchenSegmented(
                options: [PantryStorageLocation.fridge, .freezer, .pantry],
                selection: $storage
            ) { $0.displayName }
            Toggle("Set an expiry date", isOn: $hasExpiry.animation(Tide.snap))
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .tint(mood.accent)
                .frame(minHeight: Tide.hit)
            if hasExpiry {
                DatePicker("Use by", selection: $useBy, in: Date()..., displayedComponents: .date)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .frame(minHeight: Tide.hit)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tideCard()
    }

    private var includeCard: some View {
        Toggle("Add to pantry", isOn: $included)
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.text)
            .tint(mood.accent)
            .frame(minHeight: Tide.hit)
            .tideCard(padding: Tide.s4)
    }

    private var pickedCandidate: ReceiptProductPickerCandidate? {
        if case let .picked(candidate) = product {
            return candidate
        }
        return nil
    }

    private func candidateCard(_ item: FoodProduct, score: Double) -> some View {
        let isPicked = pickedCandidate?.barcode == item.barcode && pickedCandidate != nil
        return Button {
            product = .picked(.from(item, matchScore: score))
            name = item.displayName
            HapticManager.selection()
        } label: {
            VStack(spacing: Tide.s2) {
                ProductImageView(url: item.imageURL, fallbackIcon: "bag.fill", size: Tide.Kitchen.suggestionWide)
                Text(item.displayName)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: Tide.Kitchen.suggestion)
                if let brand = item.brand, !brand.isEmpty {
                    Text(brand)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .lineLimit(1)
                }
            }
            .padding(Tide.s2)
            .overlay(
                RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                    .strokeBorder(isPicked ? mood.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.displayName)\(isPicked ? ", selected" : "")")
    }

    private func loadCandidates() async {
        guard candidates.isEmpty else {
            return
        }
        let query = line.displayName.isEmpty ? line.rawText : line.displayName
        guard !line.isNonFood, !line.isFee, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        isLoadingCandidates = true
        defer { isLoadingCandidates = false }
        guard let hits = try? await provider.search(query, limit: 12) else {
            return
        }
        let scored = hits
            .filter { $0.imageURL != nil }
            .map { hit in
                (hit, ReceiptProductMatcher.compositeScore(
                    product: hit,
                    readableName: query,
                    matchedBrand: line.brand,
                    sizeValue: line.sizeValue,
                    sizeUnit: line.sizeUnit
                ))
            }
            .sorted { $0.1 > $1.1 }
        candidates = Array(scored.prefix(3)).map { (product: $0.0, score: $0.1) }
    }

    private func save() {
        onSave(ReceiptLineEditResult(
            name: name.trimmingCharacters(in: .whitespaces),
            quantity: ReceiptQuantityParser.parse(quantityText) ?? line.quantity,
            unit: unit,
            price: ReceiptQuantityParser.parse(priceText) ?? line.totalPrice,
            storage: storage,
            useBy: hasExpiry ? useBy : nil,
            included: included,
            product: product
        ))
        dismiss()
    }
}
