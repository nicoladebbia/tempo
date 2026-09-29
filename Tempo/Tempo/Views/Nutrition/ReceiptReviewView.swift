//
// ReceiptReviewView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftData
import SwiftUI
import UIKit

// MARK: - ReceiptReviewView

struct ReceiptReviewView: View {
    let receipt: Receipt
    let receiptService: any ReceiptServiceProtocol
    let pantryService: any PantryServiceProtocol
    /// Fired after a successful ingest so the presenter can re-deduct the now-
    /// fuller pantry from the active grocery list (bought items drop off "to buy").
    var onIngested: (() -> Void)?

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var ingestError: String?
    @State
    private var isIngesting = false
    /// Computed once on appear, not on every render — `isLikelyDuplicate`
    /// does a full `fetchAll()` over every stored receipt, which is too
    /// expensive to re-run on each line-confirm toggle if called directly
    /// from `body`.
    @State
    private var isLikelyDuplicate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                receiptHeader
                if isLikelyDuplicate {
                    banner(
                        text: "You may have already scanned this receipt — same store, date and total as another one on file.",
                        icon: "doc.on.doc.fill",
                        color: .tempoWarning
                    )
                }
                if let crossCheckBanner = receipt.crossCheckBanner {
                    banner(text: crossCheckBanner, icon: "exclamationmark.triangle.fill", color: .tempoWarning)
                }
                if receipt.orderedLineItems.isEmpty {
                    emptyState
                } else {
                    ForEach(receipt.orderedLineItems, id: \.id) { line in
                        ReceiptLineCard(
                            line: line,
                            storeChain: receipt.storeChain,
                            onConfirmToggle: { confirmed in
                                line.userConfirmed = confirmed
                                // Confirming a line is the natural "the user
                                // vouches for this reading" moment — learn it
                                // as a store-scoped alias (local + backend
                                // crowd table) so the SAME raw OCR text
                                // resolves to this exact name next time, even
                                // if Haiku guesses differently on a future
                                // rescan (ReceiptItemResolver layer 2).
                                if confirmed {
                                    receiptService.confirmAlias(
                                        rawText: line.rawText,
                                        storeChain: receipt.storeChain,
                                        readableName: line.displayName,
                                        canonicalFoodName: line.canonicalFoodName,
                                        barcode: line.barcode
                                    )
                                }
                            },
                            onPickProduct: { candidate, keptAsTyped in
                                if keptAsTyped {
                                    // Explicit rejection of whatever match (auto or
                                    // manual) was on this line before — clear ALL
                                    // matched-product state rather than leaving a
                                    // stale photo/brand/confidence chip showing (and
                                    // stale size feeding pantry ingest) for a product
                                    // the user just said isn't this item. Back to
                                    // plain "food-level" state, same as before any
                                    // match ever ran.
                                    line.barcode = nil
                                    line.brand = nil
                                    line.imageURL = nil
                                    line.matchConfidence = nil
                                    line.sizeValue = nil
                                    line.sizeUnit = nil
                                    line.packCount = nil
                                } else {
                                    line.displayName = candidate.readableName
                                    line.canonicalFoodName = candidate.canonicalFoodName
                                    line.barcode = candidate.barcode
                                    line.brand = candidate.brand
                                    line.imageURL = candidate.imageURL
                                    line.matchConfidence = candidate.matchConfidence
                                    if let sizeValue = candidate.sizeValue {
                                        line.sizeValue = sizeValue
                                        line.sizeUnit = candidate.sizeUnit
                                    }
                                    // The picker's candidate never carries a
                                    // pack count (`ReceiptProductPickerCandidate`
                                    // has no such field), so this is always a
                                    // DIFFERENT product than whatever the
                                    // earlier background auto-match found.
                                    // Clear any stale packCount from that prior
                                    // match — ReceiptLineItem.ingestQuantity
                                    // multiplies sizeValue * packCount *
                                    // quantity, so a leftover pack count would
                                    // silently multiply pantry ingest by the
                                    // wrong factor. Code-review finding,
                                    // round 2.
                                    line.packCount = nil
                                }
                                receiptService.confirmAlias(
                                    rawText: line.rawText,
                                    storeChain: receipt.storeChain,
                                    readableName: line.displayName,
                                    canonicalFoodName: line.canonicalFoodName,
                                    barcode: line.barcode
                                )
                            }
                        )
                    }
                }

                if let ingestError {
                    Text(ingestError)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                }

                Button {
                    ingest()
                } label: {
                    HStack {
                        if isIngesting {
                            ProgressView().tint(.white)
                        }
                        Text("Add Confirmed Lines to Pantry")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.tempoPrimary)
                .disabled(isIngesting || receipt.orderedLineItems.allSatisfy { !$0.userConfirmed || $0.isIngested })
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Review Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // .decimalPad has no Return key — without this there's no way to
            // close the keyboard except scrolling.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
                .fontWeight(.semibold)
            }
        }
        .task {
            isLikelyDuplicate = receiptService.isLikelyDuplicate(receipt)
        }
    }

    private var receiptHeader: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text(receipt.store)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(receipt.purchaseDate, format: .dateTime.month().day().year())
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
            HStack(spacing: TempoSpacing.md) {
                Label(
                    String(format: "$%.2f", receipt.totalAmount),
                    systemImage: "dollarsign.circle.fill"
                )
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                Label("\(receipt.lineItemCount) items", systemImage: "list.bullet")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            if receipt.subtotalAmount != nil || receipt.taxAmount != nil || receipt.savingsAmount != nil {
                HStack(spacing: TempoSpacing.md) {
                    if let subtotal = receipt.subtotalAmount {
                        Text("Subtotal \(String(format: "$%.2f", subtotal))")
                    }
                    if let tax = receipt.taxAmount {
                        Text("Tax \(String(format: "$%.2f", tax))")
                    }
                    if let savings = receipt.savingsAmount, savings > 0 {
                        Text("Saved \(String(format: "$%.2f", savings))")
                            .foregroundStyle(Color.tempoSignal)
                    }
                }
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func banner(text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.tempoCaption1)
            .foregroundStyle(color)
            .padding(TempoSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(Color.tempoWarning)
            Text("No line items detected")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Try rescanning with a clearer photo.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxxl)
    }

    private func ingest() {
        // Belt and braces: close the keyboard so no field is mid-edit. Edits
        // already write through per keystroke (ReceiptLineCard).
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        ingestError = nil
        isIngesting = true
        defer { isIngesting = false }
        do {
            try receiptService.ingestConfirmedLines(of: receipt, into: pantryService)
            onIngested?()
            dismiss()
        } catch {
            ingestError = error.localizedDescription
        }
    }
}

// MARK: - ReceiptLineCard

private struct ReceiptLineCard: View {
    let line: ReceiptLineItem
    let storeChain: String?
    let onConfirmToggle: (Bool) -> Void
    let onPickProduct: (ReceiptProductPickerCandidate, Bool) -> Void

    @State
    private var displayName: String
    @State
    private var quantityText: String
    @State
    private var priceText: String
    @State
    private var unit: ReceiptLineUnit
    @State
    private var isPickerPresented = false

    init(
        line: ReceiptLineItem,
        storeChain: String?,
        onConfirmToggle: @escaping (Bool) -> Void,
        onPickProduct: @escaping (ReceiptProductPickerCandidate, Bool) -> Void
    ) {
        self.line = line
        self.storeChain = storeChain
        self.onConfirmToggle = onConfirmToggle
        self.onPickProduct = onPickProduct
        _displayName = State(initialValue: line.displayName)
        _quantityText = State(initialValue: ReceiptQuantityParser.format(line.quantity))
        _priceText = State(initialValue: ReceiptQuantityParser.format(line.totalPrice))
        _unit = State(initialValue: line.unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .top, spacing: TempoSpacing.sm) {
                productThumbnail
                    .onTapGesture { isPickerPresented = true }
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Item name", text: $displayName)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .onChange(of: displayName) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
                                line.displayName = trimmed
                            }
                        }
                    if let brand = line.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { line.userConfirmed },
                    set: { onConfirmToggle($0) }
                ))
                .labelsHidden()
                .disabled(line.isIngested)
            }

            Button {
                isPickerPresented = true
            } label: {
                Label(
                    line.barcode == nil ? "Find exact product" : "Change matched product",
                    systemImage: "magnifyingglass"
                )
                .font(.tempoCaption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.tempoSignal)

            HStack(spacing: TempoSpacing.md) {
                TextField("Qty", text: $quantityText)
                    .font(.tempoCaption1)
                    .frame(maxWidth: 70)
                    .keyboardType(.decimalPad)
                    // Write through on every keystroke (like VoicePantryView):
                    // .decimalPad has no Return key, so the old .onSubmit
                    // never fired and every qty edit was silently dropped.
                    .onChange(of: quantityText) { _, newValue in
                        if let value = ReceiptQuantityParser.parse(newValue) {
                            line.quantity = value
                        }
                    }
                Picker("Unit", selection: $unit) {
                    ForEach(ReceiptLineUnit.allCases, id: \.self) { u in
                        Text(u.rawValue.uppercased()).tag(u)
                    }
                }
                .pickerStyle(.menu)
                .font(.tempoCaption1)
                .onChange(of: unit) { _, newValue in
                    line.unit = newValue
                }
                Spacer()
                HStack(spacing: 2) {
                    Text("$")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    TextField("Price", text: $priceText)
                        .font(.tempoCaption1)
                        .frame(maxWidth: 60)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: priceText) { _, newValue in
                            if let value = ReceiptQuantityParser.parse(newValue) {
                                line.totalPrice = value
                            }
                        }
                }
            }

            if let unitPrice = line.unitPrice, unitPrice > 0 {
                Text("\(String(format: "$%.2f", unitPrice)) / \(unit.rawValue)")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            HStack(spacing: TempoSpacing.sm) {
                Text("OCR raw: \(line.rawText)")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .lineLimit(1)
                Spacer()
                if let matchConfidence = line.matchConfidence {
                    matchConfidencePill(matchConfidence)
                }
                confidencePill
            }

            if line.onSale, let note = line.saleNote {
                Label(note, systemImage: "tag.fill")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoSignal)
            }

            if line.isNonFood || line.isFee {
                Label(line.isFee ? "Fee/deposit — not food" : "Not food", systemImage: "cart.badge.minus")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            if line.isIngested {
                Label("Added to pantry", systemImage: "checkmark.circle.fill")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoSuccess)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .sheet(isPresented: $isPickerPresented) {
            ReceiptProductPickerView(
                line: line,
                storeChain: storeChain
            ) { candidate, keptAsTyped in
                if !keptAsTyped {
                    displayName = candidate.readableName
                }
                onPickProduct(candidate, keptAsTyped)
                isPickerPresented = false
            }
        }
    }

    /// Product photo when a match already exists; a neutral placeholder
    /// otherwise (still tappable — that's how the picker is discovered).
    @ViewBuilder
    private var productThumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous)
        Group {
            if let urlString = line.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.tempoBorder, lineWidth: 1))
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color.tempoBgSecondary
            Image(systemName: "cart.fill")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    private var confidencePill: some View {
        let percentage = Int(line.confidence * 100)
        let color: Color = line.confidence >= 0.85
            ? .tempoSuccess
            : (line.confidence >= 0.65 ? .tempoWarning : .tempoError)
        return Text("\(percentage)%")
            .font(.tempoCaption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func matchConfidencePill(_ confidence: Double) -> some View {
        Label("\(Int(confidence * 100))% match", systemImage: "checkmark.seal.fill")
            .font(.tempoCaption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.tempoInfo.opacity(0.15))
            .foregroundStyle(Color.tempoInfo)
            .clipShape(Capsule())
    }
}

// MARK: - ReceiptQuantityParser

/// Parses the receipt qty field. `.decimalPad` types the locale's separator —
/// "1,5" on an Italian iPhone — which `Double("1,5")` rejects, so both
/// separators are accepted. Rejects empty, negative and non-numeric input
/// (caller keeps the previous value).
enum ReceiptQuantityParser {
    static func parse(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite, value >= 0 else {
            return nil
        }
        return value
    }

    /// "2" not "2.0"; up to two decimals otherwise ("0.25", "1.5").
    static func format(_ value: Double) -> String {
        // Round to 2 dp first so 2.995 → "3", never "3." after zero-stripping.
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return "\(Int(rounded))"
        }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        return text
    }
}
