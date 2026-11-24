//
// SupplementsView.swift
// Tempo
//
// Kitchen > Supplements: the shelf of what you OWN, grouped by time of day
// exactly like Today's supplements card. Every row shows name, brand, dose,
// when you take it, how many days are left and a Reorder chip when it's low.
// Tap a row for the detail page (schedule, stock, reminders, macros, "Took
// it" history, Delete). One clear "Add" menu on top: Scan barcode / Search by
// name / Quick add common / Type it. The meal-plan AI reads this shelf (see
// MealPlanPrompts.supplementShelfBlock).
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftData
import SwiftUI

// MARK: - SupplementsView

struct SupplementsView: View {
    /// Set by Today's card (and notifications) to open one supplement's detail
    /// page straight away; cleared once handled.
    var openSupplementID: Binding<UUID?>

    init(openSupplementID: Binding<UUID?> = .constant(nil)) {
        self.openSupplementID = openSupplementID
    }

    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    /// Live shelf — non-archived only, sorted by name.
    @Query(
        filter: #Predicate<Supplement> { !$0.isArchived },
        sort: \Supplement.name
    )
    private var supplements: [Supplement]

    @State private var activeSheet: ShelfSheet?
    @State private var showBarcodeScan = false
    @State private var detailTarget: Supplement?
    @State private var reorderTarget: Supplement?
    /// Quiet confirmation after a best-effort catalog share.
    @State private var catalogNote: String?

    /// One sheet at a time (a sheet swap goes through `present`).
    private enum ShelfSheet: Identifiable {
        case search
        case typeIt
        case quickAdd
        case readLabel
        case prefilled(id: UUID, dto: SupplementLookupDTO)

        var id: String {
            switch self {
            case .search: "search"
            case .typeIt: "typeIt"
            case .quickAdd: "quickAdd"
            case .readLabel: "readLabel"
            case let .prefilled(id, _): "prefilled-\(id)"
            }
        }
    }

    /// Something is presented over the page: its shaders stop.
    private var isCovered: Bool {
        activeSheet != nil || reorderTarget != nil || showBarcodeScan
    }

    var body: some View {
        let logs = fetchRecentLogs()
        let sections = shelfSections(logs: logs)
        return ScrollView(.vertical) {
            VStack(spacing: Tide.s5) {
                if !supplements.isEmpty {
                    shelfHeader(lowCount: sections.flatMap(\.rows).filter(\.needsReorder).count)
                }
                if let catalogNote {
                    KitchenNotice(systemImage: "checkmark.circle.fill", text: catalogNote, tint: Tide.Kitchen.good)
                        .accessibilityIdentifier("supplementCatalogNote")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                SupplementReorderBanner()
                if supplements.isEmpty {
                    emptyState
                } else {
                    ForEach(sections) { section in
                        sectionCard(section)
                    }
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .tidePage()
        .tideCovered(isCovered)
        .animation(Tide.snap, value: catalogNote)
        .navigationDestination(item: $detailTarget) { supplement in
            SupplementDetailView(supplement: supplement)
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .sheet(item: $reorderTarget) { supplement in
            SupplementReorderSheet(supplement: supplement)
        }
        .fullScreenCover(isPresented: $showBarcodeScan) {
            UniversalScanView(context: .supplements(shelf: supplements, onSaved: {
                try? modelContext.save()
                notifyShelfChanged()
            }))
            .environment(services)
        }
        .onAppear(perform: openRequestedSupplement)
        .onChange(of: openSupplementID.wrappedValue) { _, _ in
            openRequestedSupplement()
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: ShelfSheet) -> some View {
        switch sheet {
        case .search:
            SupplementSearchSheet(
                onPick: { dto in present(.prefilled(id: UUID(), dto: dto)) },
                onTypeIt: { present(.typeIt) },
                onReadLabel: { present(.readLabel) }
            )
            .environment(services)
        case .readLabel:
            SupplementLabelCaptureSheet(
                upc: nil,
                onResult: { dto in present(.prefilled(id: UUID(), dto: dto)) },
                onTypeIt: { present(.typeIt) }
            )
            .environment(services)
        case .typeIt:
            SupplementEditSheet(existing: nil, prefillUPC: nil) { draft in
                insert([draft])
            }
        case .quickAdd:
            SupplementQuickAddSheet(existingNames: supplements.map(\.name)) { drafts in
                insert(drafts)
            }
        case let .prefilled(_, dto):
            SupplementEditSheet(existing: nil, prefillUPC: nil, prefill: dto) { draft in
                insert([draft])
                shareWithCatalog(draft, origin: SupplementCatalogSubmitter.origin(prefillSource: dto.source, hadBarcode: false))
            }
        }
    }

    /// Best effort: a failure never touches the save that already happened.
    private func shareWithCatalog(_ draft: Supplement, origin: SupplementCatalogOrigin?) {
        guard let origin else { return }
        let service = LiveSupplementLookupService(apiClient: services.apiClient)
        Task {
            if await SupplementCatalogSubmitter.submit(draft: draft, origin: origin, using: service) {
                catalogNote = SupplementCatalogSubmitter.confirmation
                try? await Task.sleep(for: .seconds(5))
                catalogNote = nil
            }
        }
    }

    /// Swaps one sheet for another without SwiftUI dropping the second.
    private func present(_ next: ShelfSheet) {
        if activeSheet == nil {
            activeSheet = next
            return
        }
        activeSheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            activeSheet = next
        }
    }

    private func insert(_ drafts: [Supplement]) {
        for draft in drafts {
            modelContext.insert(draft)
        }
        try? modelContext.save()
        notifyShelfChanged()
    }

    /// Fires after every shelf mutation (add / edit / archive / restock) so
    /// anything that caches the shelf elsewhere — reminders, the meal-plan
    /// AI's supplement block — can react.
    private func notifyShelfChanged() {
        NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
    }

    private func openRequestedSupplement() {
        guard let id = openSupplementID.wrappedValue else { return }
        if let target = supplements.first(where: { $0.id == id }) {
            detailTarget = target
        }
        openSupplementID.wrappedValue = nil
    }

    // MARK: - Data

    /// Last `intakeWindowDays` of intake — the days-left / LOW rule is the same
    /// as the reorder banner and the Today chip.
    private func fetchRecentLogs() -> [SupplementIntakeLog] {
        let windowStart = SupplementReorderService.intakeWindowStart()
        let descriptor = FetchDescriptor<SupplementIntakeLog>(
            predicate: #Predicate<SupplementIntakeLog> { $0.day >= windowStart }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func shelfSections(logs: [SupplementIntakeLog]) -> [SupplementShelfSection] {
        guard !supplements.isEmpty else { return [] }
        let context = SupplementDayContext.build(date: Date(), modelContext: modelContext)
        let doses = SupplementScheduleEngine.schedule(supplements: supplements, context: context)
        return SupplementShelfBoard.build(supplements: supplements, doses: doses, recentLogs: logs)
    }

    // MARK: - Header

    private func shelfHeader(lowCount: Int) -> some View {
        let total = supplements.count
        return VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(alignment: .top, spacing: Tide.s4) {
                KitchenStat(value: "\(total)", label: total == 1 ? "Supplement" : "Supplements")
                if lowCount > 0 {
                    KitchenStat(value: "\(lowCount)", label: "To reorder", color: Tide.Kitchen.warn)
                }
            }
            if lowCount > 0 {
                KitchenShelfBar(parts: [
                    .init(id: "stocked", value: Double(max(total - lowCount, 0)), color: mood.accent),
                    .init(id: "low", value: Double(lowCount), color: Tide.Kitchen.warn),
                ])
            }
            Menu {
                addMenuItems()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.tidePrimary)
            .accessibilityIdentifier("supplementAddMenu")
        }
        .tideCard()
    }

    /// Every way onto the shelf. The empty page puts Scan out front as its own
    /// button, so its menu leaves that one out.
    @ViewBuilder
    private func addMenuItems(includingScan: Bool = true) -> some View {
        if includingScan {
            Button {
                showBarcodeScan = true
            } label: {
                Label("Scan barcode", systemImage: "barcode.viewfinder")
            }
        }
        Button {
            activeSheet = .search
        } label: {
            Label("Search by name", systemImage: "magnifyingglass")
        }
        Button {
            activeSheet = .readLabel
        } label: {
            Label("Read a label", systemImage: "camera.viewfinder")
        }
        .accessibilityIdentifier("supplementReadLabel")
        Button {
            activeSheet = .quickAdd
        } label: {
            Label("Quick add common", systemImage: "square.grid.2x2")
        }
        Button {
            activeSheet = .typeIt
        } label: {
            Label("Type it", systemImage: "square.and.pencil")
        }
    }

    // MARK: - Empty state

    @Environment(\.tideMood)
    private var mood

    /// Nothing owned yet: one thing to do (scan), and the other ways in one tap away.
    private var emptyState: some View {
        VStack(spacing: Tide.s5) {
            KitchenHeroDisc(systemImage: "pills")
            VStack(spacing: Tide.s2) {
                Text("No supplements yet")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "Add what you own: whey, creatine, omega-3. Your plan decides each day whether to take or skip them. Tick a dose and its calories and macros count in your day."
                )
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: Tide.s3) {
                Button {
                    showBarcodeScan = true
                } label: {
                    Label("Scan barcode", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(.tidePrimary)
                // The same menu the full shelf has on top, so the add flow
                // starts from the same control whether the shelf is empty or not.
                Menu {
                    addMenuItems(includingScan: false)
                } label: {
                    Label("More ways to add", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
                .accessibilityIdentifier("supplementAddMenu")
            }
        }
        .frame(maxWidth: .infinity)
        .tideCard(padding: Tide.s6)
    }

    // MARK: - Shelf

    private func sectionCard(_ section: SupplementShelfSection) -> some View {
        KitchenGroup(title: section.period.title, systemImage: section.period.icon) {
            ForEach(section.rows) { row in
                shelfRow(row)
            }
        }
    }

    private func shelfRow(_ row: SupplementShelfRow) -> some View {
        HStack(spacing: Tide.s2) {
            Button {
                detailTarget = row.supplement
            } label: {
                HStack(spacing: Tide.s3) {
                    Image(systemName: row.supplement.kind.icon)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(mood.accent)
                        .frame(width: Tide.Kitchen.tile, height: Tide.Kitchen.tile)
                        .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(row.supplement.name)
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                            .lineLimit(2)
                        Text(row.brandDoseLine)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .lineLimit(1)
                        Label(row.statusLine, systemImage: "clock")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: Tide.s1) {
                        if let stock = row.stockLine, !row.needsReorder {
                            Text(stock)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }
                        Image(systemName: "chevron.right")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.supplement.name), \(row.brandDoseLine), \(row.statusLine). Open details")
            .accessibilityIdentifier("supplementRow.\(row.supplement.name)")

            if row.needsReorder {
                Button {
                    reorderTarget = row.supplement
                } label: {
                    let tone = row.daysLeft == 0 ? Tide.danger : Tide.Kitchen.warn
                    Label(row.stockLine ?? "Low", systemImage: "cart")
                        .font(Tide.label)
                        .foregroundStyle(tone)
                        .padding(.horizontal, Tide.s3)
                        .padding(.vertical, Tide.s1)
                        .background(tone.opacity(0.14), in: .capsule)
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.supplement.name) running low, reorder")
                .accessibilityIdentifier("supplementReorderChip.\(row.supplement.name)")
            }
        }
    }
}
