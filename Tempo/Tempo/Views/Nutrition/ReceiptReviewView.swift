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
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
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
        KitchenList {
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
                            .listRowBackground(Tide.fill)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation(Tide.snap) {
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
                    KitchenNotice(systemImage: "exclamationmark.triangle.fill", text: ingestError, tint: Tide.danger)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .kitchenPage()
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle("Review Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar }
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
        let needsLook = model.needsLookCount
        let ready = max(model.includedCount - needsLook, 0)
        return VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(receipt.purchaseDate, format: .dateTime.month().day().year()).tideLabel()
                    Text(receipt.store.isEmpty ? "Receipt" : receipt.store)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .lineLimit(2)
                }
                Spacer(minLength: Tide.s2)
                TideNumber(String(format: "$%.2f", receipt.totalAmount), size: Tide.numeralM, relativeTo: .title)
            }
            if receipt.lineItemCount > 0 {
                KitchenShelfBar(parts: [
                    .init(id: "ready", value: Double(ready), color: Tide.Kitchen.good),
                    .init(id: "look", value: Double(needsLook), color: Tide.Kitchen.warn),
                ])
            }
            HStack(spacing: Tide.s2) {
                Text("\(receipt.lineItemCount) items")
                if let savings = receipt.savingsAmount, savings > 0 {
                    Text("·")
                    Text("Saved \(String(format: "$%.2f", savings))")
                        .foregroundStyle(Tide.Kitchen.good)
                }
            }
            .font(Tide.caption)
            .foregroundStyle(Tide.text2)
            if needsLook > 0 {
                Label("\(needsLook) need a look", systemImage: "exclamationmark.circle.fill")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.Kitchen.warn)
                    .padding(.horizontal, Tide.s3)
                    .padding(.vertical, Tide.s1)
                    .background(Tide.Kitchen.warn.opacity(0.14), in: .capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ section: ReceiptReviewSection, count: Int) -> some View {
        Label("\(section.title) · \(count)", systemImage: section.icon)
            .tideLabel(section == .needsLook ? Tide.Kitchen.warn : Tide.text2)
    }

    private func banner(text: String, icon: String) -> some View {
        KitchenNotice(systemImage: icon, text: text)
            .padding(.bottom, Tide.s1)
    }

    // MARK: - Row

    private func row(_ line: ReceiptLineItem) -> some View {
        let included = model.isIncluded(line)
        let storage = model.storage(for: line)
        let notFood = model.isNotFood(line)
        return Button {
            editingLine = line
        } label: {
            rowLayout {
                HStack(spacing: Tide.s3) {
                    ProductImageView(
                        url: model.photoURL(for: line),
                        fallbackIcon: ReceiptProductPhoto.categoryIcon(forCanonicalName: line.canonicalFoodName, isNonFood: notFood),
                        size: Tide.Kitchen.tile
                    )
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(line.displayName.isEmpty ? line.rawText : line.displayName)
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                        Text(detailText(line))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    }
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: Tide.s2)
                    }
                }
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: Tide.s1) {
                    TideNumber(
                        line.totalPrice > 0 ? String(format: "$%.2f", line.totalPrice) : "$—",
                        size: Tide.numeralS, relativeTo: .headline, weight: .semibold
                    )
                    if notFood && !included {
                        chip("Excluded", icon: "minus.circle", color: Tide.text3)
                    } else {
                        chip(storage.displayName, icon: storage.icon, color: Tide.text2)
                    }
                }
            }
            .padding(.vertical, Tide.s1)
            .frame(minHeight: Tide.hit)
            .opacity(included ? 1 : 0.55)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the editor")
    }

    /// Name and price sit side by side; at the accessibility sizes the price
    /// and shelf drop under the name so neither gets squeezed.
    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
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
        HStack(spacing: Tide.s1) {
            Image(systemName: icon)
                .accessibilityHidden(true)
            Text(text)
        }
        .font(Tide.label)
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(color)
        .padding(.horizontal, Tide.s2)
            .padding(.vertical, Tide.s1)
            .background(Tide.fill, in: .capsule)
    }

    private var emptyState: some View {
        KitchenEmpty(
            systemImage: "exclamationmark.triangle.fill",
            title: "No line items detected",
            message: "Try rescanning with a clearer photo."
        )
        .padding(.vertical, Tide.s4)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: Tide.s2) {
            if let removed = model.lastRemoved {
                HStack {
                    Text("Removed \(removed.displayName.isEmpty ? "item" : removed.displayName)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text)
                        .lineLimit(1)
                    Spacer()
                    Button("Undo") {
                        withAnimation(Tide.snap) { model.undoRemove() }
                        HapticManager.selection()
                    }
                    .font(Tide.bodyStrong)
                    .foregroundStyle(mood.accent)
                    .frame(minHeight: Tide.hit)
                }
                .padding(.horizontal, Tide.s4)
                .padding(.vertical, Tide.s1)
                .glassEffect(.regular.tint(Tide.glassControl), in: .rect(cornerRadius: Tide.tileRadius))
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
                        ProgressView().tint(Tide.ink)
                    }
                    Text(addButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.kitchenBar)
            .disabled(isIngesting || model.includedCount == 0)
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s2)
        .padding(.bottom, Tide.s2)
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
