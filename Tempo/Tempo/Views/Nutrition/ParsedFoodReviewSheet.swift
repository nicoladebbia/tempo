//
// ParsedFoodReviewSheet.swift
// Tempo
//
// The confirmation step between "the app worked out what you ate" and "it's
// saved": Quick Log text, a meal photo and a barcode all land here. You set
// when you ate it (the meal follows the time), adjust each portion with the
// ½ / 1 / 1½ / 2 chips or a gram figure, then Log. Nothing is written before.
//

import SwiftUI

struct ParsedFoodReviewSheet: View {
    let items: [ParsedFoodItem]
    let onConfirm: ([ParsedFoodItem], MealType, Date) -> Void
    let onCancel: () -> Void

    @State
    private var draft: MealReviewDraft
    /// Grams text per row while the user is typing; committed on every valid keystroke.
    @State
    private var gramsText: [String: String] = [:]
    /// Set on the first Log tap so a double-tap can't log the meal twice.
    @State
    private var didConfirm = false

    @Environment(\.dismiss)
    private var dismiss

    init(
        items: [ParsedFoodItem],
        hintedMealType: MealType?,
        hintedDate: Date?,
        onConfirm: @escaping ([ParsedFoodItem], MealType, Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.items = items
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _draft = State(initialValue: MealReviewDraft(items: items, hintedDate: hintedDate, hintedType: hintedMealType))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    whenSection
                    mealTypePicker
                    itemList
                    totalsFooter
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Confirm Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        guard !didConfirm else {
                            return
                        }
                        didConfirm = true
                        onConfirm(draft.items, draft.mealType, draft.eatenAt)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(didConfirm || draft.items.isEmpty)
                    .accessibilityIdentifier("reviewLog")
                }
            }
        }
    }

    // MARK: - When

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel("WHEN")
            HStack {
                Text(Self.relativeDay(draft.eatenAt))
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                DatePicker(
                    "Time eaten",
                    selection: Binding(get: { draft.eatenAt }, set: { draft.setEatenAt($0) }),
                    in: ...Date().addingTimeInterval(60),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .accessibilityIdentifier("reviewTime")
            }
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.sm)
            .background(Color.tempoBgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
        }
    }

    private static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }

    private var mealTypePicker: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel("MEAL TYPE")
            Picker("Meal type", selection: Binding(get: { draft.mealType }, set: { draft.setMealType($0) })) {
                ForEach(MealType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Foods

    private var itemList: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel("FOODS")
            VStack(spacing: TempoSpacing.xs) {
                ForEach(items) { item in
                    if draft.factors[item.id] != nil {
                        row(item)
                    }
                }
            }
            if draft.items.isEmpty {
                Text("Nothing left to log.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
    }

    private func row(_ original: ParsedFoodItem) -> some View {
        let current = original.scaled(by: draft.factor(for: original.id))
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(original.name)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(current.formattedPortion)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Text("\(Int(current.calories)) kcal")
                    .font(.tempoCaption1.monospacedDigit())
                    .foregroundStyle(Color.tempoTextPrimary)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { draft.remove(original.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(original.name)")
            }
            HStack(spacing: TempoSpacing.sm) {
                ForEach(MealReviewDraft.factorChoices, id: \.self) { choice in
                    chip(choice, for: original)
                }
                Spacer(minLength: 0)
                if original.quantityGrams > 0 {
                    gramsField(original, current: current)
                }
            }
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, 10)
        .background(Color.tempoBgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
    }

    private func chip(_ choice: Double, for original: ParsedFoodItem) -> some View {
        let selected = abs(draft.factor(for: original.id) - choice) < 0.001
        return Button {
            HapticManager.lightImpact()
            draft.setFactor(choice, for: original.id)
            gramsText[original.id] = nil
        } label: {
            Text(Self.chipLabel(choice))
                .font(.tempoCaption1)
                .foregroundStyle(selected ? Color.tempoInk : Color.tempoTextPrimary)
                .frame(minWidth: 28)
                .padding(.horizontal, TempoSpacing.sm)
                .padding(.vertical, TempoSpacing.xs)
                .background(selected ? Color.tempoSignal : Color.tempoBgTertiary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.chipLabel(choice)) portion")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func gramsField(_ original: ParsedFoodItem, current: ParsedFoodItem) -> some View {
        HStack(spacing: 2) {
            TextField(
                "g",
                text: Binding(
                    get: { gramsText[original.id] ?? String(Int(current.quantityGrams.rounded())) },
                    set: { text in
                        gramsText[original.id] = text
                        if let grams = Double(text.replacingOccurrences(of: ",", with: ".")) {
                            draft.setGrams(grams, for: original.id)
                            if draft.factor(for: original.id) >= MealReviewDraft.maxFactor {
                                gramsText[original.id] = nil // capped: show the real figure
                            }
                        }
                    }
                )
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(.tempoCaption1.monospacedDigit())
            .frame(width: 44)
            Text("g")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(.horizontal, TempoSpacing.sm)
        .padding(.vertical, TempoSpacing.xs)
        .background(Color.tempoBgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sm, style: .continuous))
    }

    static func chipLabel(_ factor: Double) -> String {
        switch factor {
        case 0.5: "½"
        case 1.5: "1½"
        default: factor == factor.rounded() ? "\(Int(factor))" : String(factor)
        }
    }

    // MARK: - Totals

    private var totalsFooter: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack {
                sectionLabel("TOTAL")
                Spacer()
                Text("\(draft.totalCalories) kcal")
                    .font(.tempoSubheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextPrimary)
            }
            HStack(spacing: TempoSpacing.lg) {
                Text("P \(Int(draft.totalProtein))g").foregroundStyle(Color.tempoMacroProtein)
                Text("C \(Int(draft.totalCarbs))g").foregroundStyle(Color.tempoMacroCarbs)
                Text("F \(Int(draft.totalFat))g").foregroundStyle(Color.tempoMacroFat)
                Spacer()
            }
            .font(.tempoCaption1.monospacedDigit())
        }
        .padding(.top, TempoSpacing.sm)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.tempoModuleTag)
            .tracking(TempoTracking.drillLabel)
            .foregroundStyle(Color.tempoTextSecondary)
    }
}
