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

struct SupplementsView: View {
    @Environment(\.modelContext)
    private var modelContext

    /// Live shelf — non-archived only, sorted by name.
    @Query(
        filter: #Predicate<Supplement> { !$0.isArchived },
        sort: \Supplement.name
    )
    private var supplements: [Supplement]

    @State private var showAddSheet = false
    @State private var editing: Supplement?

    var body: some View {
        ZStack {
            Color.tempoBgPrimary.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TempoSpacing.lg) {
                    headerCard
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
            SupplementEditSheet(existing: nil) { draft in
                modelContext.insert(draft)
                try? modelContext.save()
            }
        }
        .sheet(item: $editing) { supp in
            SupplementEditSheet(existing: supp) { _ in
                try? modelContext.save()
            }
        }
    }

    // MARK: - Header

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
            Button {
                showAddSheet = true
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.tempoPrimary)
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
            Text("Add what you own — whey, creatine, omega-3. Your plan will decide each day whether to take or skip them, and count protein powder toward your macros.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxxl)
    }

    // MARK: - Shelf

    private var shelfSection: some View {
        VStack(spacing: TempoSpacing.sm) {
            ForEach(supplements) { supp in
                supplementRow(supp)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func supplementRow(_ supp: Supplement) -> some View {
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
                        Text(supp.name)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                        if supp.takeDaily {
                            tag("DAILY", color: Color.tempoSignal)
                        }
                        if supp.isRunningLow {
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
        if supp.proteinGramsPerServing > 0 {
            parts.append("\(Int(supp.proteinGramsPerServing))g protein")
        }
        if supp.servingsRemaining > 0 {
            parts.append("\(Int(supp.servingsRemaining)) left")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Edit / Add sheet

private struct SupplementEditSheet: View {
    /// Non-nil when editing an existing shelf item; nil when adding a new one.
    let existing: Supplement?
    /// Called with the supplement to persist (a fresh insert when adding, or
    /// the mutated existing item when editing).
    let onSave: (Supplement) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var name: String
    @State private var kind: SupplementKind
    @State private var dose: String
    @State private var proteinPerServingText: String
    @State private var servingsText: String
    @State private var takeDaily: Bool
    @State private var notes: String

    init(existing: Supplement?, onSave: @escaping (Supplement) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _kind = State(initialValue: existing?.kind ?? .protein)
        _dose = State(initialValue: existing?.dosePerServing ?? "")
        _proteinPerServingText = State(
            initialValue: (existing?.proteinGramsPerServing ?? 0) > 0
                ? String(Int(existing?.proteinGramsPerServing ?? 0)) : ""
        )
        _servingsText = State(
            initialValue: (existing?.servingsRemaining ?? 0) > 0
                ? String(Int(existing?.servingsRemaining ?? 0)) : ""
        )
        _takeDaily = State(initialValue: existing?.takeDaily ?? SupplementKind.protein.defaultsToDaily)
        _notes = State(initialValue: existing?.userNotes ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Supplement") {
                    TextField("Name (e.g. Whey Isolate)", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(SupplementKind.allCases, id: \.rawValue) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    .onChange(of: kind) { _, newKind in
                        // Seed the daily default from the kind only when adding;
                        // don't stomp an explicit choice on an existing item.
                        if existing == nil {
                            takeDaily = newKind.defaultsToDaily
                        }
                    }
                }
                Section("Dosing") {
                    TextField("Dose per serving (e.g. 25 g, 5 g, 1000 mg)", text: $dose)
                    if kind == .protein {
                        TextField("Protein grams per serving", text: $proteinPerServingText)
                            .keyboardType(.numberPad)
                    }
                    TextField("Servings left (optional)", text: $servingsText)
                        .keyboardType(.numberPad)
                    Toggle("Take every day by default", isOn: $takeDaily)
                }
                Section("Notes (optional)") {
                    TextField("e.g. only on training days", text: $notes, axis: .vertical)
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
        let protein = Double(proteinPerServingText) ?? 0
        let servings = Double(servingsText) ?? 0
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        if let existing {
            existing.name = trimmedName
            existing.kind = kind
            existing.dosePerServing = dose
            existing.proteinGramsPerServing = max(0, protein)
            existing.servingsRemaining = max(0, servings)
            existing.takeDaily = takeDaily
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
                takeDaily: takeDaily,
                userNotes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            onSave(new)
        }
        HapticManager.notification(.success)
        dismiss()
    }
}
