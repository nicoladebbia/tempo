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
    }

    // MARK: - Picking

    private var pickingContent: some View {
        VStack(spacing: 0) {
            if available.isEmpty {
                emptyAllOnShelf
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    Text("Tap what you already own. Your plan will decide each day whether to take it.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TempoSpacing.screenEdge)
                        .padding(.top, TempoSpacing.md)
                        .padding(.bottom, TempoSpacing.lg)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 96), spacing: TempoSpacing.sm)],
                        spacing: TempoSpacing.sm
                    ) {
                        ForEach(available) { item in
                            quickAddChip(item)
                        }
                    }
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.bottom, TempoSpacing.xxxxl)
                }

                Button("Add \(selectedIDs.count)") {
                    step = .details
                }
                .buttonStyle(.tempoPrimary)
                .disabled(selectedIDs.isEmpty)
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.md)
                .background(Color.tempoBgPrimary)
            }
        }
        .background(Color.tempoBgPrimary)
    }

    private var emptyAllOnShelf: some View {
        VStack(spacing: TempoSpacing.md) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.tempoAsh)
            Text("You've already got every common one")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Add anything else manually or by scanning its barcode.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TempoSpacing.screenEdge)
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
            VStack(spacing: TempoSpacing.xs) {
                Image(systemName: item.icon)
                    .font(.tempoTitle3)
                    .foregroundStyle(isSelected ? Color.tempoTextInverse : Color.tempoSignal)
                Text(item.name)
                    .font(.tempoCaption2)
                    .foregroundStyle(isSelected ? Color.tempoTextInverse : Color.tempoTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(TempoSpacing.sm)
            .background(isSelected ? Color.tempoSignal : Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Color.tempoBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Details

    private var detailsContent: some View {
        Form {
            Section {
                Text("Optional — skip this if you don't know it yet. Your plan doesn't need it.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            ForEach(chosenItems) { item in
                Section(item.name) {
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
            .buttonStyle(.tempoPrimary)
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.md)
            .background(Color.tempoBgPrimary)
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
