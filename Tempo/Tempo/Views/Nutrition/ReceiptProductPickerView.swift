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
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
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
                    // Rows the size of the results that are coming.
                    VStack(spacing: Tide.s2) {
                        ForEach(0 ..< 5, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                                .fill(Tide.fill)
                                .frame(height: Tide.Kitchen.row + Tide.s4)
                        }
                    }
                    .shimmer()
                    .padding(Tide.edge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Searching")
                } else if let searchError {
                    KitchenFailure(
                        title: "Search didn't work",
                        message: searchError,
                        retryTitle: "Try again",
                        retry: { Task { await search() } }
                    )
                    .padding(Tide.edge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    KitchenStateHero(
                        systemImage: "magnifyingglass",
                        title: "No match",
                        message: "No matching products found. You can keep the name as typed below."
                    )
                    .padding(Tide.edge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: Tide.s2) {
                            ForEach(Array(results.enumerated()), id: \.offset) { index, entry in
                                candidateRow(entry.product, score: entry.score, isBest: index == 0)
                            }
                        }
                        .padding(Tide.edge)
                    }
                }
            }
            .kitchenSheet()
            .safeAreaBar(edge: .bottom, spacing: 0) {
                Button {
                    onPick(.keepAsTyped, true)
                } label: {
                    Text("Keep \"\(line.displayName.isEmpty ? line.rawText : line.displayName)\" as typed")
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
                .padding(Tide.edge)
            }
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
        HStack(spacing: Tide.s2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
            TextField("Search food or brand", text: $query)
                .font(Tide.body)
                .onSubmit {
                    Task { await search() }
                }
            if !query.isEmpty {
                Button {
                    Task { await search() }
                } label: {
                    Text("Search")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(mood.accent)
                        .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                }
            }
        }
        .padding(.horizontal, Tide.s4)
        .frame(minHeight: Tide.hit)
        .glassEffect(.regular.tint(Tide.glassControl), in: .rect(cornerRadius: Tide.tileRadius))
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s2)
    }

    private func candidateRow(_ product: FoodProduct, score: Double?, isBest: Bool) -> some View {
        Button {
            onPick(.from(product, matchScore: score), false)
        } label: {
            HStack(spacing: Tide.s2) {
                candidateThumbnail(product)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(product.displayName)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .lineLimit(2)
                    HStack(spacing: Tide.s1) {
                        if let brand = product.brand, !brand.isEmpty {
                            Text(brand)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
                        }
                        if let size = product.quantityLabel {
                            Text(size)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
                        }
                    }
                    if typeSize.isAccessibilitySize, let score {
                        Text("\(Int(score * 100))% match")
                            .font(Tide.caption.monospacedDigit())
                            .foregroundStyle(score >= 0.6 ? Tide.Kitchen.good : Tide.text3)
                    }
                }
                Spacer(minLength: Tide.s2)
                // At the accessibility sizes the match goes under the name so
                // the name keeps the whole row.
                if !typeSize.isAccessibilitySize {
                    matchColumn(score: score, isBest: isBest)
                }
            }
            .frame(minHeight: Tide.hit)
            .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
        }
        .buttonStyle(.plain)
    }

    private func matchColumn(score: Double?, isBest: Bool) -> some View {
        VStack(alignment: .trailing, spacing: Tide.s1) {
            if let score {
                Text("\(Int(score * 100))%")
                    .font(Tide.caption.monospacedDigit())
                    .foregroundStyle(score >= 0.6 ? Tide.Kitchen.good : Tide.text3)
            }
            if isBest, let score, score >= 0.6 {
                KitchenTag(text: "Best match", tint: Tide.Kitchen.good)
            }
        }
    }

    private func candidateThumbnail(_ product: FoodProduct) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
        return Group {
            if let url = product.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        Tide.fill
                    }
                }
            } else {
                Tide.fill
            }
        }
        .frame(width: Tide.Kitchen.thumb, height: Tide.Kitchen.thumb)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Tide.hairline, lineWidth: 1))
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
