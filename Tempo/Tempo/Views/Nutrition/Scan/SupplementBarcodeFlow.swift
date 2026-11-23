//
// SupplementBarcodeFlow.swift
// Tempo
//
// Barcode mode for the supplement shelf. Uses the shared ScanBarcodeSurface
// but hits the supplement lookup endpoint instead of the food catalog. Scan → confirm
// card (brand, name, dose, servings/container, certifications) → Add → Scan
// another, in a loop until the user taps Done. A hit that matches something
// already on the shelf (by UPC or name) offers a restock instead of a
// duplicate row. Lookup order: your shelf, the on-device cache of earlier hits,
// then the backend (NIH DSLD by UPC, Open Facts). When nothing is found the
// user is NEVER at a dead end: Photograph the label (AI reads the Supplement
// Facts, then the review screen; the result is shared with Tempo's catalog), Search by name, or Type it with the barcode already filled in.
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftData
import SwiftUI
import UIKit

struct SupplementBarcodeFlow: View {
    /// Non-archived shelf, for duplicate-by-UPC/name detection.
    let shelf: [Supplement]
    /// Called after every add/restock so the caller can persist / refresh.
    let onSaved: () -> Void
    /// Injected for tests/previews; nil in production builds the live
    /// service from `ServiceContainer.apiClient` on first lookup.
    var injectedLookupService: (any SupplementLookupServicing)?

    init(shelf: [Supplement], onSaved: @escaping () -> Void, injectedLookupService: (any SupplementLookupServicing)? = nil) {
        self.shelf = shelf
        self.onSaved = onSaved
        self.injectedLookupService = injectedLookupService
    }

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood

    @State private var scanState: ScanState = .scanning
    @State private var network = NetworkStatus()
    @State private var addedCount = 0
    @State private var flowSheet: FlowSheet?
    /// Quiet confirmation after a best-effort catalog share.
    @State private var catalogNote: String?
    /// Items inserted during THIS scan session. `shelf` is a snapshot handed
    /// in when the cover was presented and only picks up new adds once the
    /// parent's `@Query` refreshes and re-diffs this cover — not guaranteed
    /// before the next scan. Duplicate detection checks this too, so scanning
    /// the same product twice in one session (buying two bottles) offers a
    /// restock instead of creating a second row.
    @State private var sessionAdditions: [Supplement] = []

    /// One sheet at a time; swapping goes through `present`.
    private enum FlowSheet: Identifiable {
        case manual(upc: String?)
        case search(upc: String?)
        case readLabel(upc: String?)
        case prefilled(id: UUID, dto: SupplementLookupDTO)

        var id: String {
            switch self {
            case .manual: "manual"
            case .search: "search"
            case .readLabel: "readLabel"
            case let .prefilled(id, _): "prefilled-\(id)"
            }
        }
    }

    private enum ScanState {
        case scanning
        case loading(String)
        case duplicate(dto: SupplementLookupDTO, existing: Supplement)
        case found(SupplementLookupDTO)
        case notFound(upc: String)
        case failed(upc: String, message: String)
        case invalid(message: String)
    }

    var body: some View {
        ZStack {
            TidePageBackground()
            switch scanState {
            case .scanning:
                ScanBarcodeSurface(
                    prompt: "Point at the label's barcode",
                    detail: scannerDetail,
                    fallbackActions: [
                        ScanFallbackAction(title: "Search by name") { flowSheet = .search(upc: nil) },
                        ScanFallbackAction(title: "Type it") { flowSheet = .manual(upc: nil) },
                    ]
                ) { barcode in
                    lookUp(barcode)
                }
            case let .loading(code):
                loadingContent("Looking up \(code)…")
            case let .duplicate(dto, existing):
                duplicateContent(dto: dto, existing: existing)
            case let .found(dto):
                foundContent(dto)
            case let .notFound(upc):
                unresolvedContent(
                    icon: "barcode.viewfinder",
                    title: "Not in any database yet",
                    message: "\(upc.isEmpty ? "This product" : "Barcode \(upc)") isn't listed. Photograph the label and Tempo reads it for you, or add it yourself. Takes a minute.",
                    upc: upc
                )
            case let .failed(upc, message):
                unresolvedContent(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't look that up",
                    message: message,
                    upc: upc,
                    canRetry: true
                )
            case let .invalid(message):
                unresolvedContent(
                    icon: "barcode.viewfinder",
                    title: "That barcode looks off",
                    message: message,
                    upc: nil
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(addedCount == 0 ? "Done" : "Done (\(addedCount))") {
                    dismiss()
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("scanDone")
            }
        }
        .sheet(item: $flowSheet) { sheet in
            sheetContent(sheet)
        }
        .task {
            await network.monitor()
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: FlowSheet) -> some View {
        switch sheet {
        case let .manual(upc):
            SupplementEditSheet(existing: nil, prefillUPC: upc) { draft in
                saveDraft(draft, origin: SupplementCatalogSubmitter.origin(prefillSource: nil, hadBarcode: !(upc ?? "").isEmpty))
            }
        case let .prefilled(_, dto):
            SupplementEditSheet(existing: nil, prefillUPC: nil, prefill: dto) { draft in
                saveDraft(draft, origin: SupplementCatalogSubmitter.origin(prefillSource: dto.source, hadBarcode: false))
            }
        case let .readLabel(upc):
            SupplementLabelCaptureSheet(
                upc: upc,
                onResult: { dto in present(.prefilled(id: UUID(), dto: dto)) },
                onTypeIt: { present(.manual(upc: upc)) },
                injectedService: injectedLookupService
            )
            .environment(services)
        case let .search(upc):
            SupplementSearchSheet(
                onPick: { dto in
                    // A barcode that led here belongs to the product the user picked.
                    let withCode = upc.map { dto.withUPC($0) } ?? dto
                    present(.prefilled(id: UUID(), dto: withCode))
                },
                onTypeIt: { present(.manual(upc: upc)) },
                onReadLabel: { present(.readLabel(upc: upc)) },
                injectedService: injectedLookupService
            )
            .environment(services)
        }
    }

    private var scannerDetail: String? {
        var parts: [String] = []
        if addedCount > 0 { parts.append("\(addedCount) added — scan another or tap Done") }
        if let catalogNote { parts.append(catalogNote) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func present(_ next: FlowSheet) {
        guard flowSheet != nil else {
            flowSheet = next
            return
        }
        flowSheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            flowSheet = next
        }
    }

    private func saveDraft(_ draft: Supplement, origin: SupplementCatalogOrigin? = nil) {
        modelContext.insert(draft)
        try? modelContext.save()
        sessionAdditions.append(draft)
        onSaved()
        addedCount += 1
        HapticManager.notification(.success)
        resetScanner()
        if let origin {
            shareWithCatalog(draft, origin: origin)
        }
    }

    /// Best effort: a failure never touches the save that already happened.
    private func shareWithCatalog(_ draft: Supplement, origin: SupplementCatalogOrigin) {
        let service = injectedLookupService ?? LiveSupplementLookupService(apiClient: services.apiClient)
        Task {
            if await SupplementCatalogSubmitter.submit(draft: draft, origin: origin, using: service) {
                catalogNote = SupplementCatalogSubmitter.confirmation
                try? await Task.sleep(for: .seconds(6))
                catalogNote = nil
            }
        }
    }

    private func loadingContent(_ text: String) -> some View {
        VStack(spacing: Tide.s4) {
            ProgressView().controlSize(.large)
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
        }
    }

    // MARK: - Confirm card

    private func foundContent(_ dto: SupplementLookupDTO) -> some View {
        VStack(spacing: Tide.s6) {
            Spacer()
            VStack(spacing: Tide.s2) {
                Image(systemName: (SupplementKind(rawValue: dto.kind) ?? .other).icon)
                    .font(Tide.largeTitle)
                    .foregroundStyle(mood.accent)
                    .padding(.bottom, Tide.s1)
                    .accessibilityHidden(true)
                if let brand = dto.brand, !brand.isEmpty {
                    Text(brand)
                        .tideLabel(Tide.text3)
                }
                Text(dto.name)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                Text(detailLine(dto))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                if !dto.certifications.isEmpty {
                    HStack(spacing: Tide.s1) {
                        ForEach(dto.certifications, id: \.self) { cert in
                            certBadge(cert)
                        }
                    }
                    .padding(.top, Tide.s1)
                }
                if let source = Self.sourceName(dto) {
                    Text(source)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
                if dto.source == "tempo", let catalogID = dto.catalogID {
                    SupplementReportButton(catalogID: catalogID, service: LiveSupplementLookupService(apiClient: services.apiClient))
                }
                Text("UPC \(dto.upc)")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .padding(.top, Tide.s1)
            }
            .frame(maxWidth: .infinity)
            .tideCard(padding: Tide.s4)
            .padding(.horizontal, Tide.edge)

            VStack(spacing: Tide.s3) {
                Button("Add to Shelf") { add(dto) }
                    .buttonStyle(.tidePrimary)
                Button("Scan again") { resetScanner() }
                    .buttonStyle(.tideGlass)
            }
            .padding(.horizontal, Tide.s10)
            Spacer()
        }
    }

    private static func sourceName(_ dto: SupplementLookupDTO) -> String? {
        if dto.source == "tempo", dto.disputed == true { return SupplementEditSheet.disputedLine }
        return switch dto.source {
        case "tempo":
            dto.communityConfirmations.map { "Added by Tempo users · confirmed by \($0). Check it against your label." }
                ?? "Added by Tempo users. Check it against your label."
        case "dsld": "NIH supplement label database"
        case "openfoodfacts", "openproductsfacts", "openbeautyfacts": "Open Facts database"
        case "shelf": "From your shelf"
        default: nil
        }
    }

    private func certBadge(_ text: String) -> some View {
        KitchenTag(text: text, tint: Tide.Kitchen.good)
    }

    private func detailLine(_ dto: SupplementLookupDTO) -> String {
        var parts: [String] = [(SupplementKind(rawValue: dto.kind) ?? .other).displayName]
        if let dose = dto.dosePerServing, !dose.isEmpty {
            parts.append(dose)
        }
        if let servings = dto.servingsPerContainer, servings > 0 {
            parts.append("\(Int(servings)) servings/container")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Duplicate

    private func duplicateContent(dto: SupplementLookupDTO, existing: Supplement) -> some View {
        VStack(spacing: Tide.s4) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(Tide.largeTitle)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
            Text("Already on your shelf")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
            Text("You already have \(existing.name). Restocked instead of adding a new item?")
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tide.s10)
            VStack(spacing: Tide.s3) {
                Button("Restocked") { restock(dto: dto, existing: existing) }
                    .buttonStyle(.tidePrimary)
                Button("Add as new anyway") { scanState = .found(dto) }
                    .buttonStyle(.tideGlass)
                Button("Scan again") { resetScanner() }
                    .buttonStyle(.tideGlass)
            }
            .padding(.horizontal, Tide.s10)
            Spacer()
        }
    }

    // MARK: - Not found / failed / unavailable

    /// Never a dead end: every road out is a labelled button.
    private func unresolvedContent(
        icon: String,
        title: String,
        message: String,
        upc: String?,
        canRetry: Bool = false
    ) -> some View {
        ScrollView {
            VStack(spacing: Tide.s4) {
                Image(systemName: icon)
                    .font(Tide.largeTitle)
                    .foregroundStyle(Tide.text3)
                    .padding(.top, Tide.s8)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                Text(message)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Tide.s6)
                VStack(spacing: Tide.s3) {
                    if canRetry, let upc {
                        Button {
                            lookUp(upc)
                        } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.tidePrimary)
                        .accessibilityIdentifier("supplementRetryLookup")
                    }
                    if canRetry {
                        photographButton(upc: upc).buttonStyle(.tideGlass)
                    } else {
                        photographButton(upc: upc).buttonStyle(.tidePrimary)
                    }
                    Button {
                        flowSheet = .search(upc: upc)
                    } label: {
                        Label("Search by name", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("supplementSearchByName")
                    Button {
                        flowSheet = .manual(upc: upc)
                    } label: {
                        Label("Type it", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("supplementTypeIt")
                    Button {
                        resetScanner()
                    } label: {
                        Label("Scan again", systemImage: "barcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                }
                .padding(.horizontal, Tide.s10)
                .padding(.bottom, Tide.s8)
            }
        }
    }

    private func photographButton(upc: String?) -> some View {
        Button {
            flowSheet = .readLabel(upc: upc)
        } label: {
            Label("Photograph the label", systemImage: "camera.viewfinder")
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("supplementPhotographLabel")
    }

    // MARK: - Actions

    private func lookUp(_ barcode: String) {
        let code = barcode.filter(\.isNumber)
        guard !code.isEmpty else {
            return
        }
        if case .loading = scanState {
            return
        }
        scanState = .loading(code)
        HapticManager.mediumImpact()
        let service = injectedLookupService ?? LiveSupplementLookupService(apiClient: services.apiClient)
        Task {
            let outcome = await SupplementLookupRunner.run(
                upc: code,
                isOffline: network.isOffline,
                using: service,
                shelf: shelf + sessionAdditions,
                cache: SupplementLookupCache()
            )
            switch outcome {
            case let .found(dto):
                if let existing = Supplement.duplicate(forUPC: dto.upc, name: dto.name, in: shelf + sessionAdditions) {
                    HapticManager.warning()
                    scanState = .duplicate(dto: dto, existing: existing)
                } else {
                    HapticManager.success()
                    scanState = .found(dto)
                }
            case .notFound:
                HapticManager.warning()
                scanState = .notFound(upc: code)
            case .offline:
                HapticManager.warning()
                scanState = .failed(
                    upc: code,
                    message: "You're offline. Type it in now and fill in the rest later, or try again when you have signal."
                )
            case let .invalid(message):
                HapticManager.warning()
                scanState = .invalid(message: message)
            case let .failed(message):
                HapticManager.error()
                scanState = .failed(upc: code, message: message)
            }
        }
    }

    private func add(_ dto: SupplementLookupDTO) {
        let supp = Supplement(lookup: dto)
        modelContext.insert(supp)
        try? modelContext.save()
        sessionAdditions.append(supp)
        onSaved()
        addedCount += 1
        HapticManager.notification(.success)
        resetScanner()
    }

    private func restock(dto: SupplementLookupDTO, existing: Supplement) {
        let containerSize = dto.servingsPerContainer ?? existing.servingsPerContainer ?? 0
        existing.restock(fromContainerSize: containerSize)
        // A rebuy can be a different container size than last time — always
        // take the freshly scanned size when we have one, not just the
        // first-ever value, so the reorder baseline doesn't go stale.
        if let size = dto.servingsPerContainer {
            existing.servingsPerContainer = size
        }
        if existing.brand == nil, let brand = dto.brand {
            existing.brand = brand
        }
        if existing.upc == nil {
            existing.upc = dto.upc
        }
        try? modelContext.save()
        onSaved()
        addedCount += 1
        HapticManager.notification(.success)
        resetScanner()
    }

    private func resetScanner() {
        scanState = .scanning
    }
}
