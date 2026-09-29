//
// ReceiptProductPickerView.swift
// Tempo
//
// Sheet presented when the user taps a receipt review row to pick the
// EXACT product behind a line (Round 2 item 3 — wiring ReceiptProductMatcher
// + size inference into the review flow end to end). Shows Open Food Facts
// candidates with photos, lets the user re-search by name/brand, and always
// offers "Keep as typed" for when none of the candidates are right. The
// choice is handed back to the caller (ReceiptReviewView), which applies it
// to the line and feeds ReceiptItemResolver's alias-learning layer.
//

import SwiftUI

// MARK: - ReceiptProductPickerCandidate

/// What the picker hands back — either a real OFF product pick or a
/// "keep as typed" placeholder (caller checks `keptAsTyped` separately).
struct ReceiptProductPickerCandidate: Sendable {
    let readableName: String
    let canonicalFoodName: String
    let barcode: String?
    let brand: String?
    let imageURL: String?
    let matchConfidence: Double?
    let sizeValue: Double?
    let sizeUnit: String?

    /// Builds a candidate straight from an OFF `FoodProduct` search hit.
    static func from(_ product: FoodProduct, matchScore: Double?) -> ReceiptProductPickerCandidate {
        let size = product.quantityLabel.flatMap(ReceiptSizeMath.parseValueAndUnit(fromLabel:))
        return ReceiptProductPickerCandidate(
            readableName: product.displayName,
            canonicalFoodName: FoodCanonicalizer.canonicalize(product.displayName),
            barcode: product.barcode,
            brand: product.brand,
            imageURL: product.imageURL?.absoluteString,
            matchConfidence: matchScore,
            sizeValue: size?.value,
            sizeUnit: size?.unit
        )
    }

    /// The "keep as typed" placeholder — caller must check `keptAsTyped`
    /// (the second closure argument) rather than reading this candidate's
    /// fields, since none of them are meaningful here.
    static let keepAsTyped = ReceiptProductPickerCandidate(
        readableName: "",
        canonicalFoodName: "",
        barcode: nil,
        brand: nil,
        imageURL: nil,
        matchConfidence: nil,
        sizeValue: nil,
        sizeUnit: nil
    )
}

// MARK: - ReceiptProductPickerView

struct ReceiptProductPickerView: View {
    let line: ReceiptLineItem
    let storeChain: String?
    /// (candidate, keptAsTyped).
    let onPick: (ReceiptProductPickerCandidate, Bool) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var query: String
    @State
    private var results: [(product: FoodProduct, score: Double?)] = []
    @State
    private var isSearching = false
    @State
    private var searchError: String?

    private let provider: any FoodProductProviding

    init(
        line: ReceiptLineItem,
        storeChain: String?,
        provider: (any FoodProductProviding)? = nil,
        onPick: @escaping (ReceiptProductPickerCandidate, Bool) -> Void
    ) {
        self.line = line
        self.storeChain = storeChain
        self.onPick = onPick
        self.provider = provider ?? OpenFoodFactsClient()
        _query = State(initialValue: line.displayName.isEmpty ? line.rawText : line.displayName)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let searchError {
                    Text(searchError)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    Text("No matching products found. You can keep the name as typed below.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .multilineTextAlignment(.center)
                        .padding(TempoSpacing.lg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: TempoSpacing.sm) {
                            ForEach(Array(results.enumerated()), id: \.offset) { _, entry in
                                candidateRow(entry.product, score: entry.score)
                            }
                        }
                        .padding(TempoSpacing.screenEdge)
                    }
                }

                Button {
                    onPick(.keepAsTyped, true)
                } label: {
                    Text("Keep \"\(line.displayName.isEmpty ? line.rawText : line.displayName)\" as typed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
                .padding(TempoSpacing.screenEdge)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Find Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await search()
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.tempoTextTertiary)
            TextField("Search food or brand", text: $query)
                .font(.tempoBody)
                .onSubmit {
                    Task { await search() }
                }
            if !query.isEmpty {
                Button {
                    Task { await search() }
                } label: {
                    Text("Search")
                        .font(.tempoCaption1.weight(.semibold))
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
    }

    private func candidateRow(_ product: FoodProduct, score: Double?) -> some View {
        Button {
            onPick(.from(product, matchScore: score), false)
        } label: {
            HStack(spacing: TempoSpacing.sm) {
                candidateThumbnail(product)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .lineLimit(2)
                    HStack(spacing: TempoSpacing.xs) {
                        if let brand = product.brand, !brand.isEmpty {
                            Text(brand)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                        if let size = product.quantityLabel {
                            Text(size)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                }
                Spacer()
                if let score {
                    Text("\(Int(score * 100))%")
                        .font(.tempoCaption2)
                        .foregroundStyle(score >= 0.6 ? Color.tempoSuccess : Color.tempoTextTertiary)
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func candidateThumbnail(_ product: FoodProduct) -> some View {
        let shape = RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous)
        return Group {
            if let url = product.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        Color.tempoBgSecondary
                    }
                }
            } else {
                Color.tempoBgSecondary
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.tempoBorder, lineWidth: 1))
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            // Rank against this line's own readable name/size/price so the
            // best match still surfaces first even for a free-text search
            // that isn't the original brand+name query.
            let hits = try await provider.search(trimmed, limit: 15)
            results = hits.map { product in
                (product, ReceiptProductMatcher.compositeScore(
                    product: product,
                    readableName: line.displayName.isEmpty ? line.rawText : line.displayName,
                    matchedBrand: line.brand,
                    sizeValue: line.sizeValue,
                    sizeUnit: line.sizeUnit
                ))
            }
            .sorted { $0.1 > $1.1 }
        } catch {
            searchError = "Couldn't search right now. Check your connection and try again."
            results = []
        }
    }
}
