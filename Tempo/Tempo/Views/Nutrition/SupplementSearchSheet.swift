//
// SupplementSearchSheet.swift
// Tempo
//
// "Search by name": type a brand or product ("thorne magnesium", "gold
// standard whey") and pick it from the NIH supplement label database (the
// same source the barcode lookup uses) or from the common-supplements list.
// A pick hands a `SupplementLookupDTO` back; the caller opens the edit sheet
// prefilled with it, so nothing lands on the shelf unchecked. No result is
// never a dead end: "Type it yourself" is always on screen.
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftUI

struct SupplementSearchSheet: View {
    /// Called with the product the user picked. The caller swaps this sheet for
    /// the next one (the sheet does not dismiss itself).
    let onPick: (SupplementLookupDTO) -> Void
    /// "Type it yourself" — the caller opens the blank form.
    let onTypeIt: () -> Void
    /// "Photograph the label" — the caller opens the label-photo sheet.
    /// Nil hides the button.
    var onReadLabel: (() -> Void)?
    var injectedService: (any SupplementLookupServicing)?

    @Environment(\.dismiss)
    private var dismiss
    @Environment(ServiceContainer.self)
    private var services

    @State private var query = ""
    @State private var hits: [SupplementSearchHit] = []
    @State private var isSearching = false
    @State private var isOpening: String?
    @State private var message: String?
    @FocusState private var focused: Bool

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var commonMatches: [SupplementQuickAddItem] {
        guard trimmed.count >= 2 else { return [] }
        return SupplementQuickAddCatalog.items.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var service: any SupplementLookupServicing {
        injectedService ?? LiveSupplementLookupService(apiClient: services.apiClient)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: TempoSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.tempoTextTertiary)
                        TextField("Brand + product, e.g. Thorne magnesium", text: $query)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($focused)
                            .accessibilityIdentifier("supplementSearchField")
                        if isSearching {
                            ProgressView()
                        }
                    }
                }

                if !commonMatches.isEmpty {
                    Section("Common supplements") {
                        ForEach(commonMatches) { item in
                            Button {
                                onPick(Self.dto(from: item))
                            } label: {
                                resultRow(
                                    icon: item.icon, title: item.name,
                                    subtitle: [item.dose, item.macroSummary].compactMap { $0 }.joined(separator: " · ")
                                )
                            }
                        }
                    }
                }

                if !hits.isEmpty {
                    Section("Supplements") {
                        ForEach(hits) { hit in
                            Button {
                                open(hit)
                            } label: {
                                resultRow(
                                    icon: (SupplementKind(rawValue: hit.kind) ?? .other).icon,
                                    title: hit.name,
                                    subtitle: [hit.brand, hit.netContents].compactMap { $0 }.joined(separator: " · "),
                                    busy: isOpening == hit.id,
                                    badge: hit.origin.badge
                                )
                            }
                            .disabled(isOpening != nil)
                        }
                    }
                }

                Section {
                    if let message {
                        Label(message, systemImage: "info.circle")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    } else if trimmed.count >= 2, !isSearching, hits.isEmpty, commonMatches.isEmpty {
                        Label("Nothing found for \"\(trimmed)\". Try the brand and the product name, or photograph the label.", systemImage: "magnifyingglass")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    if let onReadLabel {
                        Button {
                            onReadLabel()
                        } label: {
                            Label("Photograph the label", systemImage: "camera.viewfinder")
                        }
                        .accessibilityIdentifier("supplementSearchReadLabel")
                    }
                    Button {
                        onTypeIt()
                    } label: {
                        Label("Can't find it? Type it yourself", systemImage: "square.and.pencil")
                    }
                    .accessibilityIdentifier("supplementSearchTypeIt")
                }
            }
            .navigationTitle("Search supplements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: trimmed) {
                await search()
            }
            .onAppear { focused = true }
        }
    }

    private func resultRow(icon: String, title: String, subtitle: String, busy: Bool = false, badge: String? = nil) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(Color.tempoSignal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .multilineTextAlignment(.leading)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                if let badge {
                    Text(badge)
                        .font(.tempoCaption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .padding(.horizontal, TempoSpacing.xs)
                        .padding(.vertical, 1)
                        .background(Color.tempoSurfaceElevated)
                        .clipShape(Capsule())
                }
            }
            Spacer()
            if busy {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
    }

    private func search() async {
        message = nil
        guard trimmed.count >= 2 else {
            hits = []
            return
        }
        // Debounce: a keystroke cancels the task before it hits the network.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        // A newer keystroke's search owns the spinner; a cancelled one leaves it.
        defer {
            if !Task.isCancelled {
                isSearching = false
            }
        }
        do {
            let found = try await service.search(query: trimmed)
            guard !Task.isCancelled else { return }
            hits = found
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            hits = []
            message = "Couldn't reach the supplement databases. Check your connection, or type it yourself."
        }
    }

    private func open(_ hit: SupplementSearchHit) {
        isOpening = hit.id
        Task {
            defer { isOpening = nil }
            do {
                let dto = try await service.label(id: hit.id)
                onPick(dto)
            } catch {
                message = "Couldn't open that label. Try again, or type it yourself."
            }
        }
    }

    static func dto(from item: SupplementQuickAddItem) -> SupplementLookupDTO {
        SupplementLookupDTO(
            upc: "", brand: nil, name: item.name, kind: item.kind.rawValue,
            dosePerServing: item.dose, servingsPerContainer: nil,
            proteinGramsPerServing: item.proteinGrams > 0 ? item.proteinGrams : nil,
            caloriesPerServing: item.calories > 0 ? item.calories : nil,
            carbsGramsPerServing: item.carbsGrams > 0 ? item.carbsGrams : nil,
            fatGramsPerServing: item.fatGrams > 0 ? item.fatGrams : nil,
            certifications: [], source: "catalog"
        )
    }
}
