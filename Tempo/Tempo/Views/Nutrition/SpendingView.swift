//
// SpendingView.swift
// Tempo
//
// One page for what the groceries cost: this week's spend against the budget
// with eight weeks of bars to tap through, and every scanned receipt below it.
// It replaces the Receipts list and the Spend History sheet, which were two
// screens on the same data. Receipts that need a look come first; a receipt
// opens its review, swipes away with a few seconds to Undo, and a failed one
// can be retried.
//

import SwiftData
import SwiftUI

struct SpendingView: View {
    @Bindable
    var viewModel: NutritionTabViewModel

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    /// The week the card reads (its Monday). Nil is this week.
    @State
    private var selectedWeek: Date?
    @State
    private var retryingReceiptID: UUID?
    @State
    private var errorMessage: String?
    @State
    private var showScan = false
    /// False until the first read of receipts and spend, so the empty page
    /// never flashes before the numbers arrive.
    @State
    private var didLoad = false

    private let pending = KitchenPendingReceipts.shared

    private var summary: SpendingSummary {
        SpendingSummary(weeks: viewModel.groceryStoreModeState.weeklySpend)
    }

    /// Every receipt except the ones deleted and waiting out their Undo.
    private var receipts: [Receipt] {
        viewModel.receiptState.receipts.filter { !pending.isHidden($0.id) }
    }

    private var needsAttention: [Receipt] {
        receipts.filter { $0.ocrStatus == .awaitingReview || $0.ocrStatus == .failed }
    }

    private var others: [Receipt] {
        receipts.filter { $0.ocrStatus != .awaitingReview && $0.ocrStatus != .failed }
    }

    var body: some View {
        Group {
            if !didLoad {
                loading
            } else if let error = viewModel.receiptState.loadError, receipts.isEmpty, !summary.hasSpend {
                KitchenFailure(title: "Couldn't load your receipts", message: error, retry: reload)
                    .padding(.horizontal, Tide.edge)
                    .frame(maxHeight: .infinity)
            } else if receipts.isEmpty, !summary.hasSpend {
                ScrollView {
                    KitchenEmpty(
                        systemImage: "receipt",
                        title: "No spending yet",
                        message: "Scan a grocery receipt and your weekly spend builds up here."
                    )
                    .padding(.horizontal, Tide.edge)
                    .padding(.top, Tide.s6)
                }
                .scrollIndicators(.hidden)
            } else {
                page
            }
        }
        .tidePage()
        .kitchenBottomBar {
            if canScan {
                Button {
                    showScan = true
                } label: {
                    Label("Scan a receipt", systemImage: "doc.text.viewfinder")
                }
                .buttonStyle(.kitchenBar)
                .accessibilityIdentifier("spendingScanReceipt")
            }
        }
        .sheet(isPresented: $showScan) {
            scanSheet
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
        .task {
            viewModel.attachPhase7Services(modelContext: modelContext, services: services)
        }
        .onAppear {
            reload()
            didLoad = true
        }
        .accessibilityIdentifier("spendingPage")
    }

    private var canScan: Bool {
        viewModel.receiptService != nil && viewModel.pantryService != nil
    }

    /// Reads receipts and the weekly totals again (both pages of numbers come from the same rows).
    private func reload() {
        viewModel.reloadReceipts()
        viewModel.loadGroceryWeeklySpendHistory(hiding: pending.hidden)
    }

    // MARK: Page

    private var page: some View {
        KitchenList {
            Section { hero }
            if !needsAttention.isEmpty {
                Section {
                    notice
                    ForEach(needsAttention, id: \.id) { receiptLink($0) }
                } header: {
                    sectionHeader("Needs attention", trailing: "\(needsAttention.count)")
                }
            }
            if !others.isEmpty {
                Section {
                    ForEach(others, id: \.id) { receiptLink($0) }
                } header: {
                    sectionHeader("Receipts", trailing: "\(receipts.count) in all")
                }
            } else if summary.hasSpend, receipts.isEmpty {
                Section {
                    Text("This spend comes from purchases you added by hand. Scanned receipts show up here.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Tide.s3)
        .listSectionMargins(.horizontal, Tide.edge)
        .scrollIndicators(.hidden)
        .refreshable {
            reload()
        }
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        TideSectionLabel(title: title, trailing: trailing)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: Tide.s2, leading: 0, bottom: Tide.s1, trailing: 0))
    }

    private var loading: some View {
        VStack(spacing: Tide.s3) {
            RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
                .fill(Tide.fill)
                .frame(height: 240)
            ForEach(0 ..< 2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous)
                    .fill(Tide.fill)
                    .frame(height: Tide.Kitchen.row + Tide.s4)
            }
        }
        .shimmer()
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s2)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading spending")
    }

    // MARK: Hero

    /// The week you are reading: its total big, where it stands against the
    /// budget, and the eight weeks as bars to tap.
    private var hero: some View {
        let weeks = summary.weeks
        let week = summary.week(selectedWeek)
        return VStack(alignment: .leading, spacing: Tide.s4) {
            if let week {
                TideSectionLabel(title: title(of: week), trailing: subtitle(of: week))
                VStack(alignment: .leading, spacing: Tide.s2) {
                    total(week)
                    Text(SpendingSummary.budgetLine(week))
                        .font(Tide.body)
                        .foregroundStyle(week.isOverBudget ? Tide.danger : Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .explains(.fuelSpendingWeek.showing(SpendingSummary.money(week.totalUSD)))
                if let cap = week.budgetCapUSD {
                    TideLevelBar(
                        progress: min(1, week.totalUSD / Double(max(cap, 1))),
                        color: week.isOverBudget ? Tide.danger : mood.accent,
                        height: Tide.bar
                    )
                    .accessibilityHidden(true)
                }
            }
            if weeks.count > 1 {
                KitchenSpendTrend(
                    weeks: weeks,
                    selection: Binding(
                        get: { selectedWeek ?? summary.current?.id },
                        set: { selectedWeek = $0 }
                    )
                )
            }
            if let footer = summary.footer {
                Text(footer)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .explains(.fuelSpendingAverage)
            } else {
                Text("Confirmed receipts and purchases you add count toward your spend.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard()
        .listRowInsets(EdgeInsets(top: Tide.s1, leading: 0, bottom: Tide.s1, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("spendingHero")
    }

    private func total(_ week: GroceryWeeklySpend) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s3))
        return layout {
            TideNumber(
                SpendingSummary.money(week.totalUSD),
                size: typeSize.isAccessibilitySize ? Tide.numeralM : Tide.numeralL,
                relativeTo: .largeTitle,
                color: week.isOverBudget ? Tide.danger : Tide.text
            )
            if week.isOverBudget {
                KitchenTag(text: "Over", tint: Tide.danger)
            }
        }
    }

    private func title(of week: GroceryWeeklySpend) -> String {
        if week.id == summary.current?.id {
            return "This week"
        }
        return "Week of \(week.weekStartDate.formatted(date: .abbreviated, time: .omitted))"
    }

    /// For this week, the Monday it started on; a past week says its date in the title.
    private func subtitle(of week: GroceryWeeklySpend) -> String? {
        guard week.id == summary.current?.id else {
            return nil
        }
        return "from \(week.weekStartDate.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Receipts that wait for a look are not in the spend yet: say so, once.
    @ViewBuilder
    private var notice: some View {
        let waiting = receipts.filter { $0.ocrStatus == .awaitingReview }.count
        if waiting > 0 {
            KitchenNotice(
                systemImage: "eye",
                text: waiting == 1
                    ? "1 receipt needs a look. It counts toward your spend once you confirm it."
                    : "\(waiting) receipts need a look. They count toward your spend once you confirm them."
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Tide.s1, leading: 0, bottom: Tide.s1, trailing: 0))
            .listRowSeparator(.hidden)
        }
    }

    // MARK: Receipts

    /// A scanned receipt opens its review screen; one with nothing to review is just a row.
    @ViewBuilder
    private func receiptLink(_ receipt: Receipt) -> some View {
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
                        reload()
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
                        KitchenTag(text: statusLabel(receipt.ocrStatus), tint: statusColor(receipt.ocrStatus))
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
                TideNumber(SpendingSummary.money(receipt.totalAmount), size: Tide.numeralS, relativeTo: .headline, weight: .semibold)
                Text(FuelWords.count(receipt.lineItemCount, "item"))
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
        .contextMenu {
            if receipt.ocrStatus == .failed {
                Button {
                    Task { await retry(receipt) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) {
                delete(receipt)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("spendingReceiptRow")
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

    // MARK: Actions

    /// Hides the receipt now and deletes it for good a few seconds later,
    /// unless Undo is tapped first: its photo and lines are untouched until then.
    private func delete(_ receipt: Receipt) {
        guard let service = viewModel.receiptService else {
            return
        }
        let id = receipt.id
        let name = receipt.store.isEmpty ? "Receipt" : "\(receipt.store) receipt"
        let viewModel = viewModel
        let pending = pending
        pending.schedule(
            id: id,
            delete: { try? service.delete(receipt) },
            finished: {
                viewModel.reloadReceipts()
                viewModel.loadGroceryWeeklySpendHistory(hiding: pending.hidden)
            }
        )
        viewModel.loadGroceryWeeklySpendHistory(hiding: pending.hidden)
        KitchenUndo.offer("\(name) deleted.") {
            pending.undo(id)
            viewModel.loadGroceryWeeklySpendHistory(hiding: pending.hidden)
        }
    }

    private func retry(_ receipt: Receipt) async {
        guard let service = viewModel.receiptService else {
            return
        }
        retryingReceiptID = receipt.id
        defer { retryingReceiptID = nil }
        do {
            try await service.retryStructuring(receipt)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Scan

    @ViewBuilder
    private var scanSheet: some View {
        if let receiptService = viewModel.receiptService,
           let pantryService = viewModel.pantryService
        {
            UniversalScanView(context: .pantryReceipt(
                receiptService: receiptService,
                pantryService: pantryService,
                onIngested: {
                    reload()
                    viewModel.reloadPantry()
                    viewModel.reapplyPantryToGrocery()
                }
            ))
        } else {
            Text("Scan unavailable. Open the Pantry section first.")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .padding(Tide.s4)
                .kitchenSheet()
        }
    }
}
