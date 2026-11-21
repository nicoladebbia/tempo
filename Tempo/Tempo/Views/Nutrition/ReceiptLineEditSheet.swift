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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: TempoSpacing.md) {
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
                            size: 56
                        )
                        TextField("Item name", text: $name)
                            .font(.tempoBody)
                    }
                    Text("On receipt: \(line.rawText)")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                if !candidates.isEmpty {
                    Section("Is it this one?") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: TempoSpacing.md) {
                                ForEach(Array(candidates.enumerated()), id: \.offset) { _, entry in
                                    candidateCard(entry.product, score: entry.score)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        Button("Find another product") { showFullPicker = true }
                            .font(.tempoCaption1)
                    }
                } else if isLoadingCandidates {
                    Section("Is it this one?") { ProgressView() }
                } else {
                    Section {
                        Button("Find exact product") { showFullPicker = true }
                    }
                }

                Section("Amount") {
                    HStack {
                        TextField("Qty", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 80)
                        Picker("Unit", selection: $unit) {
                            ForEach(ReceiptLineUnit.allCases, id: \.self) { value in
                                Text(value.rawValue.uppercased()).tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        Text("$").foregroundStyle(Color.tempoTextSecondary)
                        TextField("Price", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                    }
                }

                Section("Where does it go?") {
                    Picker("Storage", selection: $storage) {
                        ForEach([PantryStorageLocation.fridge, .freezer, .pantry], id: \.self) { location in
                            Text(location.displayName).tag(location)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Set an expiry date", isOn: $hasExpiry.animation())
                    if hasExpiry {
                        DatePicker("Use by", selection: $useBy, in: Date()..., displayedComponents: .date)
                    }
                }

                Section {
                    Toggle("Add to pantry", isOn: $included)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
            VStack(spacing: 6) {
                ProductImageView(url: item.imageURL, fallbackIcon: "bag.fill", size: 72)
                Text(item.displayName)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 92)
                if let brand = item.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .lineLimit(1)
                }
            }
            .padding(6)
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                    .strokeBorder(isPicked ? Color.tempoSignal : Color.clear, lineWidth: 2)
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
