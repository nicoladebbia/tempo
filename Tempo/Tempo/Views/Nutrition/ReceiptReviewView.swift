//
// ReceiptReviewView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
// One-handed review: header card, items grouped (Needs a look first, then
// food by storage, then Not food), tap a row to edit, swipe to remove with
// Undo, one big "Add N items to pantry" button at the bottom.
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
    private var model: ReceiptReviewModel
    @State
    private var editingLine: ReceiptLineItem?
    @State
    private var ingestError: String?
    @State
    private var isIngesting = false
    /// Computed once on appear, not on every render — `isLikelyDuplicate`
    /// does a full `fetchAll()` over every stored receipt.
    @State
    private var isLikelyDuplicate = false

    init(
        receipt: Receipt,
        receiptService: any ReceiptServiceProtocol,
        pantryService: any PantryServiceProtocol,
        onIngested: (() -> Void)? = nil
    ) {
        self.receipt = receipt
        self.receiptService = receiptService
        self.pantryService = pantryService
        self.onIngested = onIngested
        _model = State(initialValue: ReceiptReviewModel(receipt: receipt))
    }

    var body: some View {
        List {
            Section {
                headerCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if isLikelyDuplicate || receipt.crossCheckBanner != nil {
                Section {
                    if isLikelyDuplicate {
                        banner(
                            text: "You may have already scanned this receipt — same store, date and total as another one on file.",
                            icon: "doc.on.doc.fill"
                        )
                    }
                    if let crossCheckBanner = receipt.crossCheckBanner {
                        banner(text: crossCheckBanner, icon: "exclamationmark.triangle.fill")
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            let sections = model.sections()
            if sections.isEmpty {
                Section { emptyState.listRowBackground(Color.clear) }
            }
            ForEach(sections, id: \.section) { group in
                Section {
                    ForEach(group.lines, id: \.id) { line in
                        row(line)
                            .listRowBackground(Color.tempoSurfaceCard)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation(.easeOut(duration: TempoAnimation.smallDuration)) {
                                        model.remove(line)
                                    }
                                    HapticManager.lightImpact()
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    sectionHeader(group.section, count: group.lines.count)
                }
            }
            if let ingestError {
                Section {
                    Text(ingestError)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                        .listRowBackground(Color.clear)
                }
            }
            Color.clear.frame(height: 90)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Review Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .sheet(item: $editingLine) { line in
            ReceiptLineEditSheet(
                line: line,
                edits: model.edit(for: line),
                defaultStorage: model.storage(for: line),
                storeChain: receipt.storeChain
            ) { result in
                apply(result, to: line)
            }
        }
        .task {
            isLikelyDuplicate = receiptService.isLikelyDuplicate(receipt)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(receipt.store.isEmpty ? "Receipt" : receipt.store)
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "$%.2f", receipt.totalAmount))
                    .font(.tempoTitle3.monospacedDigit())
                    .foregroundStyle(Color.tempoTextPrimary)
            }
            HStack(spacing: TempoSpacing.sm) {
                Text(receipt.purchaseDate, format: .dateTime.month().day().year())
                Text("·")
                Text("\(receipt.lineItemCount) items")
                if let savings = receipt.savingsAmount, savings > 0 {
                    Text("·")
                    Text("Saved \(String(format: "$%.2f", savings))")
                        .foregroundStyle(Color.tempoSuccess)
                }
            }
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoTextSecondary)
            if model.needsLookCount > 0 {
                Label("\(model.needsLookCount) need a look", systemImage: "exclamationmark.circle.fill")
                    .font(.tempoCaption1.weight(.semibold))
                    .foregroundStyle(Color.tempoWarning)
                    .padding(.horizontal, TempoSpacing.sm)
                    .padding(.vertical, 4)
                    .background(Color.tempoWarning.opacity(0.14), in: Capsule())
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ section: ReceiptReviewSection, count: Int) -> some View {
        Label("\(section.title) · \(count)", systemImage: section.icon)
            .font(.tempoModuleTag)
            .foregroundStyle(section == .needsLook ? Color.tempoWarning : Color.tempoTextSecondary)
            .textCase(nil)
    }

    private func banner(text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoWarning)
            .padding(TempoSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tempoWarning.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            .padding(.bottom, TempoSpacing.xs)
    }

    // MARK: - Row

    private func row(_ line: ReceiptLineItem) -> some View {
        let included = model.isIncluded(line)
        let storage = model.storage(for: line)
        let notFood = model.isNotFood(line)
        return Button {
            editingLine = line
        } label: {
            HStack(spacing: TempoSpacing.md) {
                ProductImageView(
                    url: model.photoURL(for: line),
                    fallbackIcon: ReceiptProductPhoto.categoryIcon(forCanonicalName: line.canonicalFoodName, isNonFood: notFood)
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.displayName.isEmpty ? line.rawText : line.displayName)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .lineLimit(2)
                    Text(detailText(line))
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: TempoSpacing.sm)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(line.totalPrice > 0 ? String(format: "$%.2f", line.totalPrice) : "$—")
                        .font(.tempoBody.monospacedDigit())
                        .foregroundStyle(Color.tempoTextPrimary)
                    if notFood && !included {
                        chip("Excluded", icon: "minus.circle", color: .tempoTextTertiary)
                    } else {
                        chip(storage.displayName, icon: storage.icon, color: .tempoTextSecondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .opacity(included ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the editor")
    }

    private func detailText(_ line: ReceiptLineItem) -> String {
        var parts = [ReceiptQuantityParser.format(line.quantity) + " " + line.unit.rawValue]
        if let size = line.sizeValue, let unit = line.sizeUnit {
            parts.append(ReceiptQuantityParser.format(size) + " " + unit)
        }
        if let brand = line.brand, !brand.isEmpty {
            parts.append(brand)
        }
        return parts.joined(separator: " · ")
    }

    private func chip(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.tempoCaption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.tempoBgSecondary, in: Capsule())
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

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: TempoSpacing.sm) {
            if let removed = model.lastRemoved {
                HStack {
                    Text("Removed \(removed.displayName.isEmpty ? "item" : removed.displayName)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .lineLimit(1)
                    Spacer()
                    Button("Undo") {
                        withAnimation(.easeOut(duration: TempoAnimation.smallDuration)) { model.undoRemove() }
                        HapticManager.selection()
                    }
                    .font(.tempoCaption1.weight(.bold))
                    .foregroundStyle(Color.tempoSignal)
                }
                .padding(.horizontal, TempoSpacing.cardPadding)
                .padding(.vertical, TempoSpacing.md)
                .background(Color.tempoSurfaceCard, in: RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: removed.id) {
                    try? await Task.sleep(for: .seconds(5))
                    withAnimation { model.dismissUndo() }
                }
            }
            Button {
                ingest()
            } label: {
                HStack {
                    if isIngesting {
                        ProgressView().tint(.white)
                    }
                    Text(addButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.tempoPrimary)
            .disabled(isIngesting || model.includedCount == 0)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.sm)
        .padding(.bottom, TempoSpacing.sm)
        .background(.bar)
    }

    private var addButtonTitle: String {
        let count = model.includedCount
        return count == 1 ? "Add 1 item to pantry" : "Add \(count) items to pantry"
    }

    // MARK: - Actions

    private func apply(_ result: ReceiptLineEditResult, to line: ReceiptLineItem) {
        let renamed = line.displayName.trimmingCharacters(in: .whitespaces) != result.name.trimmingCharacters(in: .whitespaces)
        var pickedProduct = false
        if case .picked = result.product {
            pickedProduct = true
        }
        line.displayName = result.name
        line.quantity = result.quantity
        line.unit = result.unit
        line.totalPrice = result.price
        switch result.product {
        case .unchanged:
            break
        case .keptAsTyped:
            line.barcode = nil
            line.brand = nil
            line.imageURL = nil
            line.matchConfidence = nil
            line.sizeValue = nil
            line.sizeUnit = nil
            line.packCount = nil
        case let .picked(candidate):
            line.displayName = candidate.readableName
            line.canonicalFoodName = candidate.canonicalFoodName
            line.barcode = candidate.barcode
            line.brand = candidate.brand
            line.imageURL = candidate.imageURL
            line.matchConfidence = candidate.matchConfidence
            // Always assign: a product without a size must not keep the old
            // product's size (it would inflate the pantry quantity).
            line.sizeValue = candidate.sizeValue
            line.sizeUnit = candidate.sizeUnit
            // A picked product is a different product than any earlier
            // auto-match — a stale pack count would multiply pantry ingest.
            line.packCount = nil
        }
        model.update(line) {
            $0.storage = result.storage
            $0.useBy = result.useBy
            $0.included = result.included
            $0.reviewed = true
            if case .picked = result.product {
                $0.pickedProduct = true
            } else if case .keptAsTyped = result.product {
                $0.pickedProduct = false
            }
        }
        // Saving a row is the user vouching for it: learn the store-name →
        // product mapping (local alias + backend crowd table) so the same raw
        // OCR text resolves to this product next time.
        // A rename without a product pick would teach the OLD canonical name
        // or barcode under the new text, so skip the alias then.
        if result.included, pickedProduct || !renamed {
            receiptService.confirmAlias(
                rawText: line.rawText,
                storeChain: receipt.storeChain,
                readableName: line.displayName,
                canonicalFoodName: line.canonicalFoodName,
                barcode: line.barcode
            )
        }
        HapticManager.selection()
    }

    private func ingest() {
        ingestError = nil
        isIngesting = true
        defer { isIngesting = false }
        let overrides = model.commit()
        do {
            try receiptService.ingestConfirmedLines(of: receipt, into: pantryService, overrides: overrides)
            HapticManager.success()
            onIngested?()
            dismiss()
        } catch {
            ingestError = error.localizedDescription
        }
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
