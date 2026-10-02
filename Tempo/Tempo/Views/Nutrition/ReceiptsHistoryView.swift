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

    @State private var retryingReceiptID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if viewModel.receiptState.receipts.isEmpty {
                ContentUnavailableView(
                    "No receipts yet",
                    systemImage: "receipt",
                    description: Text("Scan a grocery receipt in Kitchen > Pantry to see it here.")
                )
            } else {
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
        .navigationTitle("Receipts")
        .navigationBarTitleDisplayMode(.inline)
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

    private func receiptRow(_ receipt: Receipt) -> some View {
        HStack(spacing: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.store.isEmpty ? "Unknown store" : receipt.store)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(receipt.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
                statusBadge(receipt.ocrStatus)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "$%.2f", receipt.totalAmount))
                    .font(.tempoBody.monospacedDigit())
                    .foregroundStyle(Color.tempoTextPrimary)
                Text("\(receipt.lineItemCount) item\(receipt.lineItemCount == 1 ? "" : "s")")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(.vertical, 4)
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
                .tint(Color.tempoSignal)
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
        Text(statusLabel(status).uppercased())
            .font(.tempoCaption2.weight(.semibold))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.12))
            .clipShape(Capsule())
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
             .processing: Color.tempoTextTertiary
        case .awaitingReview: Color.tempoWarning
        case .confirmed: Color.tempoSuccess
        case .failed: Color.tempoError
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
