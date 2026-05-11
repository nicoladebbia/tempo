//
// ReceiptReviewView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

// MARK: - ReceiptReviewView

struct ReceiptReviewView: View {
    let receipt: Receipt
    let receiptService: any ReceiptServiceProtocol
    let pantryService: any PantryServiceProtocol

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var ingestError: String?
    @State
    private var isIngesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                receiptHeader
                if receipt.orderedLineItems.isEmpty {
                    emptyState
                } else {
                    ForEach(receipt.orderedLineItems, id: \.id) { line in
                        ReceiptLineCard(
                            line: line,
                            onConfirmToggle: { confirmed in
                                line.userConfirmed = confirmed
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
        .background(Color.tempoBgPrimary)
        .navigationTitle("Review Receipt")
        .navigationBarTitleDisplayMode(.inline)
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
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
        ingestError = nil
        isIngesting = true
        defer { isIngesting = false }
        do {
            try receiptService.ingestConfirmedLines(of: receipt, into: pantryService)
            dismiss()
        } catch {
            ingestError = error.localizedDescription
        }
    }
}

// MARK: - ReceiptLineCard

private struct ReceiptLineCard: View {
    let line: ReceiptLineItem
    let onConfirmToggle: (Bool) -> Void

    @State
    private var displayName: String
    @State
    private var quantityText: String

    init(line: ReceiptLineItem, onConfirmToggle: @escaping (Bool) -> Void) {
        self.line = line
        self.onConfirmToggle = onConfirmToggle
        _displayName = State(initialValue: line.displayName)
        _quantityText = State(initialValue: String(line.quantity))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                TextField("Item name", text: $displayName)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .onSubmit { line.displayName = displayName }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { line.userConfirmed },
                    set: { onConfirmToggle($0) }
                ))
                .labelsHidden()
                .disabled(line.isIngested)
            }

            HStack(spacing: TempoSpacing.md) {
                TextField("Qty", text: $quantityText)
                    .font(.tempoCaption1)
                    .frame(maxWidth: 70)
                    .keyboardType(.decimalPad)
                    .onSubmit {
                        if let v = Double(quantityText) {
                            line.quantity = v
                        }
                    }
                Text(line.unit.rawValue.uppercased())
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                Text(String(format: "$%.2f", line.totalPrice))
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            HStack(spacing: TempoSpacing.sm) {
                Text("OCR raw: \(line.rawText)")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .lineLimit(1)
                Spacer()
                confidencePill
            }

            if line.onSale, let note = line.saleNote {
                Label(note, systemImage: "tag.fill")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoSignal)
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
}
