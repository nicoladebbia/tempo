//
// ReceiptsHistoryView.swift
// Tempo
//
// Full receipt history — store, date, total, OCR status for every scanned
// receipt. Failed receipts can be retried; any receipt can be deleted
// (cascade-deletes its line items; does NOT undo pantry ingestions already
// applied, matching ReceiptServiceProtocol.delete's contract).
//

import SwiftUI

struct ReceiptsHistoryView: View {
    @Bindable
    var viewModel: NutritionTabViewModel

    @Environment(\.tideMood) private var mood
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var retryingReceiptID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        KitchenList {
            if !viewModel.receiptState.receipts.isEmpty {
                summary
                ForEach(viewModel.receiptState.receipts, id: \.id) { receipt in
                    // A scanned receipt opens its review screen — "Needs review"
                    // used to be a label with nowhere to go.
                    if let receiptService = viewModel.receiptService,
                       let pantryService = viewModel.pantryService,
                       Self.canOpen(receipt)
                    {
                        NavigationLink {
                            ReceiptReviewView(
                                receipt: receipt,
                                receiptService: receiptService,
                                pantryService: pantryService,
                                onIngested: {
                                    viewModel.reloadReceipts()
                                    viewModel.reloadPantry()
                                    // Same as from Pantry: new stock shrinks the list.
                                    viewModel.reapplyPantryToGrocery()
                                }
                            )
                        } label: {
                            receiptRow(receipt)
                        }
                    } else {
                        receiptRow(receipt)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .tidePage()
        .overlay {
            // Outside the List so the empty state isn't wrapped in a list row.
            if viewModel.receiptState.receipts.isEmpty {
                KitchenEmpty(
                    systemImage: "receipt",
                    title: "No receipts yet",
                    message: "Scan a grocery receipt from the Pantry tab to see it here."
                )
                .padding(.horizontal, Tide.edge)
            }
        }
        .alert("Couldn't retry", isPresented: .init(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            viewModel.reloadReceipts()
        }
    }

    /// What this page is for: getting receipts into the pantry. The number
    /// that matters is how many still wait for a look.
    private var summary: some View {
        let receipts = viewModel.receiptState.receipts
        let waiting = receipts.filter { $0.ocrStatus == .awaitingReview }.count
        let failed = receipts.filter { $0.ocrStatus == .failed }.count
        let done = receipts.filter { $0.ocrStatus == .confirmed }.count
        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Receipts", trailing: "\(receipts.count) in all")
            if waiting > 0 {
                TideNumber("\(waiting)", unit: waiting == 1 ? "needs review" : "need review", size: Tide.numeralL, relativeTo: .largeTitle, color: Tide.Kitchen.warn)
            } else {
                TideNumber("\(done)", unit: done == 1 ? "receipt in your pantry" : "receipts in your pantry", size: Tide.numeralL, relativeTo: .largeTitle)
            }
            KitchenShelfBar(parts: [
                .init(id: "done", value: Double(done), color: Tide.Kitchen.good),
                .init(id: "waiting", value: Double(waiting), color: Tide.Kitchen.warn),
                .init(id: "failed", value: Double(failed), color: Tide.danger),
            ])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
        .accessibilityElement(children: .combine)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func statusIcon(_ status: ReceiptOCRStatus) -> String {
        switch status {
        case .pending,
             .processing: "clock"
        case .awaitingReview: "eye"
        case .confirmed: "checkmark"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func receiptRow(_ receipt: Receipt) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s3))
        return layout {
            HStack(spacing: Tide.s3) {
                Image(systemName: statusIcon(receipt.ocrStatus))
                    .font(Tide.bodyStrong)
                    .foregroundStyle(statusColor(receipt.ocrStatus))
                    .frame(width: Tide.Kitchen.tile, height: Tide.Kitchen.tile)
                    .background(statusColor(receipt.ocrStatus).opacity(0.14), in: .rect(cornerRadius: Tide.controlRadius))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(receipt.store.isEmpty ? "Unknown store" : receipt.store)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .lineLimit(2)
                    Text(receipt.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                    HStack(spacing: Tide.s2) {
                        statusBadge(receipt.ocrStatus)
                        if retryingReceiptID == receipt.id {
                            ProgressView()
                        }
                    }
                }
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Tide.s2)
            }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: Tide.hair) {
                TideNumber(String(format: "$%.2f", receipt.totalAmount), size: Tide.numeralS, relativeTo: .headline, weight: .semibold)
                Text("\(receipt.lineItemCount) item\(receipt.lineItemCount == 1 ? "" : "s")")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }
        .padding(.vertical, Tide.s1)
        .frame(minHeight: Tide.hit)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(receipt)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            if receipt.ocrStatus == .failed {
                Button {
                    Task { await retry(receipt) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .tint(mood.accent)
            }
        }
    }

    /// Receipts with structured lines to look at: needs review, or already
    /// confirmed (to see what went in). Pending/processing/failed have none.
    static func canOpen(_ receipt: Receipt) -> Bool {
        switch receipt.ocrStatus {
        // Always openable: even with no lines read, the review screen says
        // so instead of leaving the receipt stuck on "Needs review".
        case .awaitingReview: true
        case .confirmed: receipt.lineItemCount > 0
        case .pending,
             .processing,
             .failed: false
        }
    }

    private func statusBadge(_ status: ReceiptOCRStatus) -> some View {
        KitchenTag(text: statusLabel(status), tint: statusColor(status))
    }

    private func statusLabel(_ status: ReceiptOCRStatus) -> String {
        switch status {
        case .pending: "Pending"
        case .processing: "Processing"
        case .awaitingReview: "Needs review"
        case .confirmed: "Confirmed"
        case .failed: "Failed"
        }
    }

    private func statusColor(_ status: ReceiptOCRStatus) -> Color {
        switch status {
        case .pending,
             .processing: Tide.text3
        case .awaitingReview: Tide.Kitchen.warn
        case .confirmed: Tide.Kitchen.good
        case .failed: Tide.danger
        }
    }

    private func delete(_ receipt: Receipt) {
        guard let service = viewModel.receiptService else {
            return
        }
        try? service.delete(receipt)
        viewModel.reloadReceipts()
    }

    private func retry(_ receipt: Receipt) async {
        guard let service = viewModel.receiptService else {
            return
        }
        retryingReceiptID = receipt.id
        defer { retryingReceiptID = nil }
        do {
            try await service.retryStructuring(receipt)
            viewModel.reloadReceipts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
