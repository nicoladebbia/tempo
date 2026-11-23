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
        VStack(spacing: 0) {
            if available.isEmpty {
                emptyAllOnShelf
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    Text("Tap what you already own. Your plan will decide each day whether to take it.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Tide.edge)
                        .padding(.top, Tide.s3)
                        .padding(.bottom, Tide.s4)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 96), spacing: Tide.s2)],
                        spacing: Tide.s2
                    ) {
                        ForEach(available) { item in
                            quickAddChip(item)
                        }
                    }
                    .padding(.horizontal, Tide.edge)
                    .padding(.bottom, Tide.s10)
                }

                Button("Add \(selectedIDs.count)") {
                    step = .details
                }
                .buttonStyle(.tidePrimary)
                .disabled(selectedIDs.isEmpty)
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s3)
            }
        }
    }

    private var emptyAllOnShelf: some View {
        VStack(spacing: Tide.s3) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(Tide.largeTitle)
                .foregroundStyle(Tide.text3)
            Text("You've already got every common one")
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
            Text("Add anything else manually or by scanning its barcode.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Tide.edge)
    }

    private func quickAddChip(_ item: SupplementQuickAddItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return Button {
            HapticManager.selection()
            if isSelected {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
        } label: {
            VStack(spacing: Tide.s1) {
                Image(systemName: item.icon)
                    .font(Tide.headline)
                    .foregroundStyle(isSelected ? Tide.ink : mood.accent)
                Text(item.name)
                    .font(Tide.caption)
                    .foregroundStyle(isSelected ? Tide.ink : Tide.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let macros = item.macroSummary {
                    Text(macros)
                        .font(Tide.caption)
                        .foregroundStyle(isSelected ? Tide.ink.opacity(0.8) : Tide.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(Tide.s2)
            .background(isSelected ? mood.accent : Tide.fill)
            .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Tide.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Details

    private var detailsContent: some View {
        KitchenForm {
            Section {
                Text("Optional — skip this if you don't know it yet. Your plan doesn't need it.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            ForEach(chosenItems) { item in
                KitchenFormSection(item.name) {
                    TextField("Brand (optional)", text: bindingBrand(item.id))
                    TextField("Servings in the container (optional)", text: bindingServings(item.id))
                        .keyboardType(.numberPad)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Add \(chosenItems.count) to Shelf") {
                finish()
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.vertical, Tide.s3)
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
