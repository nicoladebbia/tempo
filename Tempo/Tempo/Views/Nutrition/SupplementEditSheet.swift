//
// SupplementEditSheet.swift
// Tempo
//
// Add / edit one supplement by hand. Also the landing page of every "found
// it" path that still needs a human look: a name-search pick, a photographed
// label, a scanned barcode the databases only half-knew (`prefill`).
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftData
import SwiftUI

// MARK: - SupplementEditSheet

struct SupplementEditSheet: View {
    /// Non-nil when editing an existing shelf item; nil when adding a new one.
    let existing: Supplement?
    /// Prefills `upc` on a fresh add — set when this sheet is the fallback
    /// after a barcode scan the lookup couldn't resolve.
    let prefillUPC: String?
    /// A product found by search / label photo / barcode: starts the form filled in.
    let prefill: SupplementLookupDTO?
    /// Called with the supplement to persist (a fresh insert when adding, or
    /// the mutated existing item when editing).
    let onSave: (Supplement) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var name: String
    @State private var kind: SupplementKind
    @State private var brand: String
    @State private var dose: String
    @State private var proteinPerServingText: String
    @State private var caloriesPerServingText: String
    @State private var carbsPerServingText: String
    @State private var fatPerServingText: String
    @State private var servingsText: String
    @State private var servingsPerContainerText: String
    @State private var notes: String

    init(
        existing: Supplement?,
        prefillUPC: String?,
        prefill: SupplementLookupDTO? = nil,
        onSave: @escaping (Supplement) -> Void
    ) {
        self.existing = existing
        self.prefillUPC = prefillUPC
        self.prefill = prefill
        self.onSave = onSave
        let seed = existing == nil ? prefill : nil
        _name = State(initialValue: existing?.name ?? seed?.name ?? "")
        _kind = State(initialValue: existing?.kind ?? seed.flatMap { SupplementKind(rawValue: $0.kind) } ?? .protein)
        _brand = State(initialValue: existing?.brand ?? seed?.brand ?? "")
        _dose = State(initialValue: existing?.dosePerServing ?? seed?.dosePerServing ?? "")
        _proteinPerServingText = State(initialValue: Self.macroText(existing?.proteinGramsPerServing ?? seed?.proteinGramsPerServing))
        _caloriesPerServingText = State(initialValue: Self.macroText(existing?.caloriesPerServing ?? seed?.caloriesPerServing))
        _carbsPerServingText = State(initialValue: Self.macroText(existing?.carbsGramsPerServing ?? seed?.carbsGramsPerServing))
        _fatPerServingText = State(initialValue: Self.macroText(existing?.fatGramsPerServing ?? seed?.fatGramsPerServing))
        let left = existing?.servingsRemaining ?? seed?.servingsPerContainer ?? 0
        _servingsText = State(initialValue: left > 0 ? String(Int(left)) : "")
        let perContainer = existing?.servingsPerContainer ?? seed?.servingsPerContainer ?? 0
        _servingsPerContainerText = State(initialValue: perContainer > 0 ? String(Int(perContainer)) : "")
        _notes = State(initialValue: existing?.userNotes ?? "")
    }

    /// "24", "1.5" — empty for nil / zero.
    private static func macroText(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func macroValue(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return value
    }

    private static func sourceLine(_ dto: SupplementLookupDTO) -> String? {
        switch dto.source {
        case "label": "Read from your photo. Check every number before you save."
        case "dsld": "From the NIH supplement label database. Check it against your bottle."
        case "openfoodfacts", "openproductsfacts", "openbeautyfacts": "From the Open Facts database. Check it against your bottle."
        default: nil
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let prefill, existing == nil, let line = Self.sourceLine(prefill) {
                    Section {
                        Label(line, systemImage: "sparkles")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                Section("Supplement") {
                    TextField("Name (e.g. Whey Isolate)", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    Picker("Type", selection: $kind) {
                        ForEach(SupplementKind.allCases, id: \.rawValue) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                }
                Section {
                    TextField("Calories per serving (kcal)", text: $caloriesPerServingText)
                        .keyboardType(.decimalPad)
                    TextField("Protein per serving (g)", text: $proteinPerServingText)
                        .keyboardType(.decimalPad)
                    TextField("Carbs per serving (g)", text: $carbsPerServingText)
                        .keyboardType(.decimalPad)
                    TextField("Fat per serving (g)", text: $fatPerServingText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Macros per serving")
                } footer: {
                    Text("Tick a dose and these count in today's calories and macros. Leave empty for creatine, vitamins and anything with no calories.")
                }
                Section {
                    TextField("Dose per serving (e.g. 25 g, 5 g, 1000 mg)", text: $dose)
                    TextField("Servings left (optional)", text: $servingsText)
                        .keyboardType(.numberPad)
                    TextField("Servings per container (optional)", text: $servingsPerContainerText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Details (optional)")
                } footer: {
                    Text(
                        "Your plan decides each day whether to take this and when — you don't have to schedule it. These facts just help it (servings per container is what a restock resets servings-left to)."
                    )
                }
                if let existing {
                    SupplementTimingSection(supplement: existing)
                    Section {
                        NavigationLink {
                            SupplementPicksView(supplement: existing)
                        } label: {
                            Label("Better products & where to buy", systemImage: "checkmark.seal")
                        }
                    }
                }
                Section("Notes (optional)") {
                    TextField("e.g. I get bloated with two scoops", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(existing == nil ? (prefill == nil ? "Add Supplement" : "Check & add") : "Edit Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(existing == nil ? "Add to shelf" : "Save") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
        let protein = Self.macroValue(proteinPerServingText) ?? 0
        let calories = Self.macroValue(caloriesPerServingText)
        let carbs = Self.macroValue(carbsPerServingText)
        let fat = Self.macroValue(fatPerServingText)
        let servings = Double(servingsText) ?? 0
        let servingsPerContainer = Double(servingsPerContainerText)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        if let existing {
            existing.name = trimmedName
            existing.kind = kind
            existing.brand = trimmedBrand.isEmpty ? nil : trimmedBrand
            existing.dosePerServing = dose
            existing.proteinGramsPerServing = max(0, protein)
            existing.caloriesPerServing = calories
            existing.carbsGramsPerServing = carbs
            existing.fatGramsPerServing = fat
            existing.servingsRemaining = max(0, servings)
            existing.servingsPerContainer = servingsPerContainer.map { max(0, $0) }
            // takeDaily is no longer a user choice — the AI infers daily-vs-
            // conditional from the kind. Keep it aligned to the (possibly
            // changed) kind's default so the prompt's "daily by default" hint
            // stays sensible.
            existing.takeDaily = kind.defaultsToDaily
            existing.userNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
            existing.updatedAt = Date()
            onSave(existing)
        } else {
            let new = Supplement(
                name: trimmedName,
                kind: kind,
                dosePerServing: dose,
                proteinGramsPerServing: max(0, protein),
                servingsRemaining: max(0, servings),
                userNotes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            new.caloriesPerServing = calories
            new.carbsGramsPerServing = carbs
            new.fatGramsPerServing = fat
            new.brand = trimmedBrand.isEmpty ? nil : trimmedBrand
            new.servingsPerContainer = servingsPerContainer.map { max(0, $0) }
            let code = (prefillUPC ?? prefill?.upc).flatMap { $0.isEmpty ? nil : $0 }
            new.upc = code
            if let lines = prefill?.ingredients, !lines.isEmpty {
                new.ingredientsSummary = lines.joined(separator: "\n")
            }
            onSave(new)
        }
        HapticManager.notification(.success)
        dismiss()
    }
}
