//
// SupplementQuickAddSheet.swift
// Tempo
//
// "Tap the ones you own" — the fast path onto the shelf for the ~22 common
// supplements in SupplementQuickAddCatalog. Pick step (grid of chips, already-
// owned items hidden) → optional details step (one row per pick: brand +
// servings in the container, both skippable) → inserted onto the shelf.
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftUI

struct SupplementQuickAddSheet: View {
    /// Current shelf names (including archived — no reason to re-offer a
    /// retired item's exact name either), for hiding already-owned catalog
    /// entries.
    let existingNames: [String]
    /// Called once with every `Supplement` to insert, when the user finishes
    /// (either from the details step or by skipping it).
    let onAdd: ([Supplement]) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    @State private var selectedIDs: Set<String> = []
    @State private var step: Step = .picking
    @State private var brandTexts: [String: String] = [:]
    @State private var servingsTexts: [String: String] = [:]

    private enum Step: Equatable {
        case picking
        case details
    }

    private var available: [SupplementQuickAddItem] {
        SupplementQuickAddCatalog.available(excluding: existingNames)
    }

    private var chosenItems: [SupplementQuickAddItem] {
        available.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .picking:
                    pickingContent
                case .details:
                    detailsContent
                }
            }
            .navigationTitle(step == .picking ? "Quick Add" : "A couple of details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(step == .picking ? "Cancel" : "Back") {
                        if step == .picking {
                            dismiss()
                        } else {
                            step = .picking
                        }
                    }
                }
                if step == .details {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { finish() }
                    }
                }
            }
        }
        .kitchenSheet()
    }

    // MARK: - Picking

    private var pickingContent: some View {
        Group {
            if available.isEmpty {
                emptyAllOnShelf
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Tide.s4) {
                        VStack(alignment: .leading, spacing: Tide.s1) {
                            Text("Tap what you already own.")
                                .font(Tide.title2)
                                .foregroundStyle(Tide.text)
                                .accessibilityAddTraits(.isHeader)
                            Text("Your plan will decide each day whether to take it.")
                                .font(Tide.body)
                                .foregroundStyle(Tide.text2)
                        }
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: Tide.Kitchen.suggestion), spacing: Tide.s3)],
                            spacing: Tide.s3
                        ) {
                            ForEach(available) { item in
                                quickAddChip(item)
                            }
                        }
                    }
                    .padding(.horizontal, Tide.edge)
                    .padding(.top, Tide.s3)
                    .padding(.bottom, Tide.s6)
                }
                .kitchenBottomBar {
                    // Nothing picked yet: a quiet glass hint instead of a faded button the tiles show through.
                    if selectedIDs.isEmpty {
                        Text("Pick what you own")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text2)
                            .frame(maxWidth: .infinity, minHeight: Tide.Kitchen.barButton)
                            .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
                            .transition(.opacity)
                    } else {
                        Button {
                            step = .details
                        } label: {
                            Text("Add \(selectedIDs.count)")
                                .contentTransition(.numericText())
                        }
                        .buttonStyle(.tidePrimary)
                        .transition(.opacity)
                    }
                }
                .animation(Tide.snap, value: selectedIDs.isEmpty)
            }
        }
    }

    private var emptyAllOnShelf: some View {
        KitchenEmpty(
            systemImage: "checkmark.circle",
            title: "You've already got every common one",
            message: "Add anything else manually or by scanning its barcode."
        )
        .padding(.horizontal, Tide.edge)
        .frame(maxHeight: .infinity)
    }

    /// One tile per supplement: tap to own it. A chosen tile fills with the accent and shows a tick.
    private func quickAddChip(_ item: SupplementQuickAddItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return Button {
            HapticManager.selection()
            withAnimation(Tide.snap) {
                if isSelected {
                    selectedIDs.remove(item.id)
                } else {
                    selectedIDs.insert(item.id)
                }
            }
        } label: {
            VStack(spacing: Tide.s1) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : item.icon)
                    .font(Tide.title2)
                    .foregroundStyle(isSelected ? Tide.ink : mood.accent)
                    .contentTransition(.symbolEffect(.replace))
                Text(item.name)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(isSelected ? Tide.ink : Tide.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(item.name.contains(" ") ? 2 : 1)
                    .minimumScaleFactor(Tide.labelShrink)
                if let macros = item.macroSummary {
                    Text(macros)
                        .font(Tide.caption)
                        .foregroundStyle(isSelected ? Tide.ink.opacity(0.8) : Tide.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Tide.Kitchen.suggestion)
            .padding(.horizontal, Tide.s1)
            .padding(.vertical, Tide.s2)
            .background(isSelected ? mood.accent : Tide.fill, in: .rect(cornerRadius: Tide.tileRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Tide.hairline, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Details

    /// One card per pick, two optional facts each. Skippable as a whole.
    private var detailsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Tide.s4) {
                Text("Optional. Skip this if you don't know it yet. Your plan doesn't need it.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(chosenItems) { item in
                    VStack(alignment: .leading, spacing: Tide.s3) {
                        HStack(spacing: Tide.s3) {
                            TideIconTile(systemName: item.icon)
                            Text(item.name)
                                .font(Tide.headline)
                                .foregroundStyle(Tide.text)
                        }
                        TextField("Brand (optional)", text: bindingBrand(item.id))
                            .kitchenField()
                        TextField("Servings in the container (optional)", text: bindingServings(item.id))
                            .keyboardType(.numberPad)
                            .kitchenField()
                    }
                    .tideCard()
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s3)
            .padding(.bottom, Tide.s6)
        }
        .scrollDismissesKeyboard(.interactively)
        .kitchenBottomBar {
            Button("Add \(chosenItems.count) to Shelf") {
                finish()
            }
            .buttonStyle(.tidePrimary)
        }
    }

    private func bindingBrand(_ id: String) -> Binding<String> {
        Binding(
            get: { brandTexts[id] ?? "" },
            set: { brandTexts[id] = $0 }
        )
    }

    private func bindingServings(_ id: String) -> Binding<String> {
        Binding(
            get: { servingsTexts[id] ?? "" },
            set: { servingsTexts[id] = $0 }
        )
    }

    // MARK: - Finish

    private func finish() {
        var created: [Supplement] = []
        for item in chosenItems {
            let servings = Double(servingsTexts[item.id] ?? "") ?? 0
            let supp = Supplement(
                name: item.name,
                kind: item.kind,
                dosePerServing: item.dose,
                proteinGramsPerServing: item.proteinGrams,
                servingsRemaining: servings,
                takeDaily: item.takeDaily
            )
            let brand = (brandTexts[item.id] ?? "").trimmingCharacters(in: .whitespaces)
            supp.brand = brand.isEmpty ? nil : brand
            supp.caloriesPerServing = item.calories > 0 ? item.calories : nil
            supp.carbsGramsPerServing = item.carbsGrams > 0 ? item.carbsGrams : nil
            supp.fatGramsPerServing = item.fatGrams > 0 ? item.fatGrams : nil
            if servings > 0 {
                supp.servingsPerContainer = servings
            }
            created.append(supp)
        }
        guard !created.isEmpty else {
            dismiss()
            return
        }
        onAdd(created)
        HapticManager.notification(.success)
        dismiss()
    }
}
