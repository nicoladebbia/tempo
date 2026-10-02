//
// SupplementsView.swift
// Tempo
//
// The user's supplement shelf — what they OWN (whey, creatine, omega-3, …).
// The meal-plan AI reads this shelf (see MealPlanPrompts.supplementShelfBlock)
// and makes a per-day take/skip decision, surfaced on the Today tab. This
// screen is just inventory management: add / edit / archive. Reached from the
// Pantry tab header (the two "what I own" shelves live together).
//
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.
//

import SwiftData
import SwiftUI

// MARK: - SupplementsView

struct SupplementsView: View {
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

    @State private var showAddSheet = false
    @State private var showQuickAdd = false
    @State private var showBarcodeScan = false
    @State private var editing: Supplement?

    var body: some View {
        ZStack {
            Color.tempoBgPrimary.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TempoSpacing.lg) {
                    headerCard
                    SupplementReorderBanner()
                    if supplements.isEmpty {
                        emptyState
                    } else {
                        shelfSection
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.md)
                .padding(.bottom, TempoSpacing.bottomSafe)
            }
        }
        .navigationTitle("Supplements")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            SupplementEditSheet(existing: nil, prefillUPC: nil) { draft in
                modelContext.insert(draft)
                try? modelContext.save()
                notifyShelfChanged()
            }
        }
        .sheet(item: $editing) { supp in
            SupplementEditSheet(existing: supp, prefillUPC: nil) { _ in
                try? modelContext.save()
                notifyShelfChanged()
            }
        }
        .sheet(isPresented: $showQuickAdd) {
            SupplementQuickAddSheet(existingNames: supplements.map(\.name)) { drafts in
                for draft in drafts {
                    modelContext.insert(draft)
                }
                try? modelContext.save()
                notifyShelfChanged()
            }
        }
        .fullScreenCover(isPresented: $showBarcodeScan) {
            UniversalScanView(context: .supplements(shelf: supplements, onSaved: {
                try? modelContext.save()
                notifyShelfChanged()
            }))
            .environment(services)
        }
    }

    /// Fires after every shelf mutation (add / edit / archive / restock) so
    /// anything that caches the shelf elsewhere — reminders, the meal-plan
    /// AI's supplement block — can react.
    ///
    /// Reminders and the reorder check re-read the shelf on this.
    private func notifyShelfChanged() {
        NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
    }

    // MARK: - Header

    /// Last `intakeWindowDays` of intake — the LOW badge uses the same
    /// days-of-supply rule as the reorder banner and alert.
    /// Fetched once per body evaluation and handed to every row.
    private func fetchRecentLogs() -> [SupplementIntakeLog] {
        let windowStart = SupplementReorderService.intakeWindowStart()
        let descriptor = FetchDescriptor<SupplementIntakeLog>(
            predicate: #Predicate<SupplementIntakeLog> { $0.day >= windowStart }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR SHELF")
                    .font(.tempoModuleTag)
                    .foregroundStyle(Color.tempoTextTertiary)
                Text("\(supplements.count) supplement\(supplements.count == 1 ? "" : "s")")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
            }
            Spacer()
            addMenu {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.tempoPrimary)
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    /// Toolbar "+" → a menu with all three add paths, per DESIGN_SYSTEM.md
    /// menu conventions. Shared by the header button and the empty state.
    private func addMenu(@ViewBuilder label: () -> some View) -> some View {
        Menu {
            Button {
                showQuickAdd = true
            } label: {
                Label("Quick add", systemImage: "square.grid.2x2")
            }
            Button {
                showBarcodeScan = true
            } label: {
                Label("Scan barcode", systemImage: "barcode.viewfinder")
            }
            Button {
                showAddSheet = true
            } label: {
                Label("Add manually", systemImage: "square.and.pencil")
            }
        } label: {
            label()
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
                    showQuickAdd = true
                } label: {
                    Label("Quick add", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
                Button {
                    showBarcodeScan = true
                } label: {
                    Label("Scan barcode", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
                Button("Add manually") {
                    showAddSheet = true
                }
                .buttonStyle(.tempoGhost)
            }
            .padding(.top, TempoSpacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxxl)
    }

    // MARK: - Shelf

    private var shelfSection: some View {
        let logs = fetchRecentLogs()
        return VStack(spacing: TempoSpacing.sm) {
            ForEach(supplements) { supp in
                supplementRow(supp, recentLogs: logs)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func supplementRow(_ supp: Supplement, recentLogs: [SupplementIntakeLog]) -> some View {
        Button {
            editing = supp
        } label: {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: supp.kind.icon)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoSignal)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(titleText(for: supp))
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                        if supp.takeDaily {
                            tag("DAILY", color: Color.tempoSignal)
                        }
                        if SupplementReorderService.needsReorder(for: supp, recentLogs: recentLogs) {
                            tag("LOW", color: Color.tempoWarning)
                        }
                    }
                    Text(subtitle(for: supp))
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Button(role: .destructive) {
                    supp.isArchived = true
                    supp.updatedAt = Date()
                    try? modelContext.save()
                    notifyShelfChanged()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.tempoCaption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func subtitle(for supp: Supplement) -> String {
        var parts: [String] = [supp.kind.displayName]
        if !supp.dosePerServing.isEmpty {
            parts.append(supp.dosePerServing)
        }
        if let kcal = supp.caloriesPerServing, kcal > 0 {
            parts.append("\(Int(kcal.rounded())) kcal")
        }
        if supp.proteinGramsPerServing > 0 {
            parts.append("\(Int(supp.proteinGramsPerServing.rounded()))g protein")
        }
        if supp.servingsRemaining > 0 {
            parts.append("\(Int(supp.servingsRemaining)) left")
        }
        return parts.joined(separator: " · ")
    }

    /// "Thorne · Creatine" when a brand is on file, else just the name.
    private func titleText(for supp: Supplement) -> String {
        guard let brand = supp.brand, !brand.isEmpty else {
            return supp.name
        }
        return "\(brand) · \(supp.name)"
    }
}

// MARK: - SupplementEditSheet

/// Internal (not `private`) — also presented from SupplementBarcodeScanView's
/// "add manually" fallback (404 / offline / camera unavailable).
struct SupplementEditSheet: View {
    /// Non-nil when editing an existing shelf item; nil when adding a new one.
    let existing: Supplement?
    /// Prefills `upc` on a fresh add — set when this sheet is the fallback
    /// after a barcode scan the lookup couldn't resolve.
    let prefillUPC: String?
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

    init(existing: Supplement?, prefillUPC: String?, onSave: @escaping (Supplement) -> Void) {
        self.existing = existing
        self.prefillUPC = prefillUPC
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _kind = State(initialValue: existing?.kind ?? .protein)
        _brand = State(initialValue: existing?.brand ?? "")
        _dose = State(initialValue: existing?.dosePerServing ?? "")
        _proteinPerServingText = State(initialValue: Self.macroText(existing?.proteinGramsPerServing))
        _caloriesPerServingText = State(initialValue: Self.macroText(existing?.caloriesPerServing))
        _carbsPerServingText = State(initialValue: Self.macroText(existing?.carbsGramsPerServing))
        _fatPerServingText = State(initialValue: Self.macroText(existing?.fatGramsPerServing))
        _servingsText = State(
            initialValue: (existing?.servingsRemaining ?? 0) > 0
                ? String(Int(existing?.servingsRemaining ?? 0)) : ""
        )
        _servingsPerContainerText = State(
            initialValue: (existing?.servingsPerContainer ?? 0) > 0
                ? String(Int(existing?.servingsPerContainer ?? 0)) : ""
        )
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

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle(existing == nil ? "Add Supplement" : "Edit Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
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
            new.upc = prefillUPC
            onSave(new)
        }
        HapticManager.notification(.success)
        dismiss()
    }
}
