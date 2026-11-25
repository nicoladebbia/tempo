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

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    searchField

                    if !commonMatches.isEmpty {
                        KitchenGroup(title: "Common supplements") {
                            ForEach(commonMatches) { item in
                                Button {
                                    onPick(Self.dto(from: item))
                                } label: {
                                    resultRow(
                                        icon: item.icon, title: item.name,
                                        subtitle: [item.dose, item.macroSummary].compactMap { $0 }.joined(separator: " · ")
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !hits.isEmpty {
                        KitchenGroup(title: "Supplements") {
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
                                .buttonStyle(.plain)
                                .disabled(isOpening != nil)
                            }
                        }
                    } else if isSearching, commonMatches.isEmpty {
                        searchingSkeleton
                    }

                    status

                    // Never a dead end: both ways out are always on screen.
                    VStack(spacing: Tide.s3) {
                        if let onReadLabel {
                            Button {
                                onReadLabel()
                            } label: {
                                Label("Photograph the label", systemImage: "camera.viewfinder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.tideGlass)
                            .accessibilityIdentifier("supplementSearchReadLabel")
                        }
                        Button {
                            onTypeIt()
                        } label: {
                            Label("Can't find it? Type it yourself", systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.tideGlass)
                        .accessibilityIdentifier("supplementSearchTypeIt")
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
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
        .kitchenSheet()
    }

    /// The field is the hero: big, on glass, with the spinner inside it.
    private var searchField: some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: "magnifyingglass")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
            TextField("Brand + product, e.g. Thorne magnesium", text: $query)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .accessibilityIdentifier("supplementSearchField")
            if isSearching {
                ProgressView()
            } else if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Tide.text3)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, Tide.s4)
        .frame(minHeight: Tide.Kitchen.row)
        .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .capsule)
        .animation(Tide.snap, value: isSearching)
    }

    /// Three rows of grey while the databases answer.
    private var searchingSkeleton: some View {
        VStack(spacing: Tide.s3) {
            ForEach(0 ..< 3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                    .fill(Tide.fill)
                    .frame(height: Tide.Kitchen.row)
            }
        }
        .shimmer()
        .accessibilityLabel("Searching")
    }

    @ViewBuilder
    private var status: some View {
        if let message {
            KitchenNotice(systemImage: "info.circle", text: message, tint: Tide.text2)
        } else if trimmed.count >= 2, !isSearching, hits.isEmpty, commonMatches.isEmpty {
            KitchenNotice(
                systemImage: "magnifyingglass",
                text: "Nothing found for \"\(trimmed)\". Try the brand and the product name, or photograph the label.",
                tint: Tide.text2
            )
        } else if trimmed.count < 2 {
            Text("Type a brand and a product. Results come from the NIH supplement label database and the common list.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Tide.s1)
        }
    }

    private func resultRow(icon: String, title: String, subtitle: String, busy: Bool = false, badge: String? = nil) -> some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: icon)
                .font(Tide.bodyStrong)
                .foregroundStyle(mood.accent)
                .frame(width: Tide.s6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(title)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.leading)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                if let badge {
                    KitchenTag(text: badge, tint: Tide.text3)
                }
            }
            Spacer()
            if busy {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Tide.hit)
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
