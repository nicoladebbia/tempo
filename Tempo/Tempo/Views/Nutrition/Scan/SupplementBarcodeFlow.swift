//
// SupplementBarcodeFlow.swift
// Tempo
//
// Barcode mode for the supplement shelf. Uses the shared ScanBarcodeSurface
// but hits the supplement lookup endpoint instead of the food catalog. Scan → confirm
// card (brand, name, dose, servings/container, certifications) → Add → Scan
// another, in a loop until the user taps Done. A hit that matches something
// already on the shelf (by UPC or name) offers a restock instead of a
// duplicate row. 404 / offline / any other failure drops to a manual form
// prefilled with the scanned UPC — the user should never be stuck.
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftData
import SwiftUI

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

    @State private var scanState: ScanState = .scanning
    @State private var network = NetworkStatus()
    @State private var addedCount = 0
    @State private var manualPrefillUPC: String?
    @State private var showManualAdd = false
    /// Items inserted during THIS scan session. `shelf` is a snapshot handed
    /// in when the cover was presented and only picks up new adds once the
    /// parent's `@Query` refreshes and re-diffs this cover — not guaranteed
    /// before the next scan. Duplicate detection checks this too, so scanning
    /// the same product twice in one session (buying two bottles) offers a
    /// restock instead of creating a second row.
    @State private var sessionAdditions: [Supplement] = []

    private enum ScanState {
        case scanning
        case loading(String)
        case duplicate(dto: SupplementLookupDTO, existing: Supplement)
        case found(SupplementLookupDTO)
        case notFound(upc: String)
        case failed(upc: String, message: String)
    }

    var body: some View {
        ZStack {
            Color.tempoBgPrimary.ignoresSafeArea()
            switch scanState {
            case .scanning:
                ScanBarcodeSurface(
                    prompt: "Point at the label's barcode",
                    detail: addedCount > 0 ? "\(addedCount) added — scan another or tap Done" : nil,
                    fallbackActions: [ScanFallbackAction(title: "Add manually") { openManualAdd(prefillUPC: nil) }]
                ) { barcode in
                    lookUp(barcode)
                }
            case let .loading(code):
                loadingContent(code)
            case let .duplicate(dto, existing):
                duplicateContent(dto: dto, existing: existing)
            case let .found(dto):
                foundContent(dto)
            case let .notFound(upc):
                messageContent(
                    icon: "barcode.viewfinder",
                    title: "Not in the database",
                    message: "Barcode \(upc) isn't recognized yet.",
                    primaryTitle: "Add manually",
                    primaryAction: { openManualAdd(prefillUPC: upc) }
                )
            case let .failed(upc, message):
                messageContent(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't look that up",
                    message: message,
                    primaryTitle: "Add manually",
                    primaryAction: { openManualAdd(prefillUPC: upc) }
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
        .sheet(isPresented: $showManualAdd) {
            SupplementEditSheet(existing: nil, prefillUPC: manualPrefillUPC) { draft in
                modelContext.insert(draft)
                try? modelContext.save()
                sessionAdditions.append(draft)
                onSaved()
                addedCount += 1
                resetScanner()
            }
        }
        .task {
            await network.monitor()
        }
    }

    private func loadingContent(_ code: String) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            ProgressView().controlSize(.large)
            Text("Looking up \(code)…")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    // MARK: - Confirm card

    private func foundContent(_ dto: SupplementLookupDTO) -> some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()
            VStack(spacing: TempoSpacing.sm) {
                Image(systemName: (SupplementKind(rawValue: dto.kind) ?? .other).icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.tempoSignal)
                    .padding(.bottom, TempoSpacing.xs)
                if let brand = dto.brand, !brand.isEmpty {
                    Text(brand.uppercased())
                        .font(.tempoModuleTag)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                Text(dto.name)
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .multilineTextAlignment(.center)
                Text(detailLine(dto))
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                if !dto.certifications.isEmpty {
                    HStack(spacing: TempoSpacing.xs) {
                        ForEach(dto.certifications, id: \.self) { cert in
                            certBadge(cert)
                        }
                    }
                    .padding(.top, TempoSpacing.xs)
                }
                Text("UPC \(dto.upc)")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.top, TempoSpacing.xs)
            }
            .padding(TempoSpacing.cardPadding)
            .frame(maxWidth: .infinity)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .padding(.horizontal, TempoSpacing.screenEdge)

            VStack(spacing: TempoSpacing.buttonStackVertical) {
                Button("Add to Shelf") { add(dto) }
                    .buttonStyle(.tempoPrimary)
                Button("Scan again") { resetScanner() }
                    .buttonStyle(.tempoGhost)
            }
            .padding(.horizontal, TempoSpacing.xxxxl)
            Spacer()
        }
    }

    private func certBadge(_ text: String) -> some View {
        Text(text)
            .font(.tempoCaption2)
            .fontWeight(.semibold)
            .foregroundStyle(Color.tempoSuccess)
            .padding(.horizontal, TempoSpacing.sm)
            .padding(.vertical, TempoSpacing.xxs)
            .background(Color.tempoSuccess.opacity(0.15))
            .clipShape(Capsule())
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
        VStack(spacing: TempoSpacing.lg) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.tempoAsh)
            Text("Already on your shelf")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("You already have \(existing.name). Restocked instead of adding a new item?")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.xxxxl)
            VStack(spacing: TempoSpacing.buttonStackVertical) {
                Button("Restocked") { restock(dto: dto, existing: existing) }
                    .buttonStyle(.tempoPrimary)
                Button("Add as new anyway") { scanState = .found(dto) }
                    .buttonStyle(.tempoSecondary)
                Button("Scan again") { resetScanner() }
                    .buttonStyle(.tempoGhost)
            }
            .padding(.horizontal, TempoSpacing.xxxxl)
            Spacer()
        }
    }

    // MARK: - Not found / failed / unavailable

    private func messageContent(
        icon: String,
        title: String,
        message: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoAsh)
            Text(title)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.xxxxl)
            VStack(spacing: TempoSpacing.buttonStackVertical) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.tempoPrimary)
                Button("Scan again") { resetScanner() }
                    .buttonStyle(.tempoSecondary)
            }
            .padding(.horizontal, TempoSpacing.xxxxl)
            Spacer()
        }
    }

    // MARK: - Actions

    private func openManualAdd(prefillUPC: String?) {
        manualPrefillUPC = prefillUPC
        showManualAdd = true
    }

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
            let outcome = await SupplementLookupRunner.run(upc: code, isOffline: network.isOffline, using: service)
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
                    message: "You're offline. Add it manually now — you can fill in the rest later."
                )
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
