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

    var body: some View {
        let logs = fetchRecentLogs()
        let sections = shelfSections(logs: logs)
        VStack(spacing: 0) {
            topBar(lowCount: sections.flatMap(\.rows).filter(\.needsReorder).count)
            if let catalogNote {
                Label(catalogNote, systemImage: "checkmark.circle")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.bottom, TempoSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("supplementCatalogNote")
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TempoSpacing.lg) {
                    SupplementReorderBanner()
                    if supplements.isEmpty {
                        emptyState
                    } else {
                        ForEach(sections) { section in
                            sectionCard(section)
                        }
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.sm)
                .padding(.bottom, TempoSpacing.bottomSafe)
            }
        }
        .background(Color.tempoBgPrimary.ignoresSafeArea())
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

    // MARK: - Top bar

    private func topBar(lowCount: Int) -> some View {
        HStack(alignment: .center, spacing: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR SHELF")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextTertiary)
                Text("\(supplements.count) supplement\(supplements.count == 1 ? "" : "s")" + (lowCount > 0 ? " · \(lowCount) to reorder" : ""))
                    .font(.tempoBodyBold)
                    .foregroundStyle(Color.tempoTextPrimary)
            }
            Spacer(minLength: TempoSpacing.sm)
            Menu {
                addMenuItems
            } label: {
                Label("Add", systemImage: "plus")
                    .fixedSize()
            }
            .buttonStyle(.tempoPrimary)
            .accessibilityIdentifier("supplementAddMenu")
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
    }

    @ViewBuilder
    private var addMenuItems: some View {
        Button {
            showBarcodeScan = true
        } label: {
            Label("Scan barcode", systemImage: "barcode.viewfinder")
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

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.md) {
            Image(systemName: "pills")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.tempoAsh)
            Text("No supplements yet")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(
                "Add what you own — whey, creatine, omega-3. Your plan decides each day whether to take or skip them. Tick a dose and its calories and macros count in your day."
            )
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoTextSecondary)
            .multilineTextAlignment(.center)
            VStack(spacing: TempoSpacing.buttonStackVertical) {
                Button {
                    showBarcodeScan = true
                } label: {
                    Label("Scan barcode", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
                Button {
                    activeSheet = .search
                } label: {
                    Label("Search by name", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
                Button {
                    activeSheet = .readLabel
                } label: {
                    Label("Read a label", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
                Button {
                    activeSheet = .quickAdd
                } label: {
                    Label("Quick add common", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
                Button {
                    activeSheet = .typeIt
                } label: {
                    Label("Type it", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoGhost)
            }
            .padding(.top, TempoSpacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxxl)
    }

    // MARK: - Shelf

    private func sectionCard(_ section: SupplementShelfSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(section.period.title.uppercased(), systemImage: section.period.icon)
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.bottom, TempoSpacing.xs)
            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().overlay(Color.tempoDivider)
                }
                shelfRow(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func shelfRow(_ row: SupplementShelfRow) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Button {
                detailTarget = row.supplement
            } label: {
                HStack(spacing: TempoSpacing.md) {
                    Image(systemName: row.supplement.kind.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.tempoSignal)
                        .frame(width: 36, height: 36)
                        .background(Color.tempoBgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.supplement.name)
                            .font(.tempoBodyBold)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(row.brandDoseLine)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .lineLimit(1)
                        Label(row.dose.take ? row.scheduleLine : "Skipping today", systemImage: "clock")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: TempoSpacing.xs) {
                        if let stock = row.stockLine, !row.needsReorder {
                            Text(stock)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.supplement.name), \(row.brandDoseLine), \(row.scheduleLine). Open details")
            .accessibilityIdentifier("supplementRow.\(row.supplement.name)")

            if row.needsReorder {
                Button {
                    reorderTarget = row.supplement
                } label: {
                    Label(row.stockLine ?? "Low", systemImage: "cart")
                        .font(.tempoCaption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(row.daysLeft == 0 ? Color.tempoError : Color.tempoAmber)
                        .padding(.horizontal, TempoSpacing.sm)
                        .padding(.vertical, TempoSpacing.xs)
                        .background((row.daysLeft == 0 ? Color.tempoError : Color.tempoAmber).opacity(TempoOpacity.o15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.supplement.name) running low, reorder")
                .accessibilityIdentifier("supplementReorderChip.\(row.supplement.name)")
            }
        }
        .padding(.vertical, TempoSpacing.sm)
    }
}
