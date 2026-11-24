//
// WriteRecipeView.swift
// Tempo
//
// Typed form for creating a custom Recipe by hand. Fires `onSave(recipe)`
// with a domain Recipe (source: .userCreated) when the user taps Save.
// Macros are not collected here — LocalRecipeService.add(...) calls
// recipe.recomputeMacroTotals() which sums per-ingredient values that
// FoodMacroDatabase resolves at insert time.
//

import SwiftUI

struct WriteRecipeView: View {
    var onSave: (Recipe) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    @State private var name: String = ""
    @State private var servingsText: String = "2"
    @State private var prepMinutesText: String = ""
    @State private var cookMinutesText: String = ""
    @State private var ingredientRows: [IngredientRow] = [IngredientRow()]
    @State private var stepRows: [StepRow] = [StepRow()]

    /// Width of the short number fields (servings, minutes, grams); grows with text size.
    @ScaledMetric(relativeTo: .body)
    private var numberFieldWidth: CGFloat = Tide.s10 * 2

    private struct IngredientRow: Identifiable {
        let id = UUID()
        var name: String = ""
        var displayQuantity: String = ""
        var quantityGramsText: String = ""
    }

    private struct StepRow: Identifiable {
        let id = UUID()
        var instruction: String = ""
        var durationText: String = ""
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
            && ingredientRows.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            && stepRows.contains { !$0.instruction.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                ingredientsSection
                stepsSection
            }
            .font(Tide.body)
            .tint(mood.accent)
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            // The one action sits under the thumb.
            .fuelBottomBar {
                Button("Save") { save() }
                    .buttonStyle(.tidePrimary)
                    .disabled(!canSave)
            }
            .tidePage()
            // A sheet is its own page, even when it comes up from inside one.
            .environment(\.tideInsidePage, false)
            .navigationTitle("Write Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var basicsSection: some View {
        Section {
            TextField("Recipe name", text: $name)
                .frame(minHeight: Tide.hit)
            HStack {
                Text("Servings")
                Spacer()
                TextField("2", text: $servingsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: numberFieldWidth)
            }
            .frame(minHeight: Tide.hit)
            HStack {
                Text("Prep time (min)")
                Spacer()
                TextField("optional", text: $prepMinutesText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: numberFieldWidth)
            }
            .frame(minHeight: Tide.hit)
            HStack {
                Text("Cook time (min)")
                Spacer()
                TextField("optional", text: $cookMinutesText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: numberFieldWidth)
            }
            .frame(minHeight: Tide.hit)
        } header: {
            Text("Basics").tideLabel()
        }
        .fuelRow()
    }

    /// Single-ingredient row. Extracted from ingredientsSection so the
    /// section's ForEach stays a one-line builder; combined VStack +
    /// HStack + macroCoverageBadge inline is exactly the shape that pushes
    /// SwiftUI's type-checker into timeout territory.
    private func ingredientRowView(row: Binding<IngredientRow>) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TextField("Ingredient (e.g. chicken breast)", text: row.name)
                .textInputAutocapitalization(.never)
            HStack {
                TextField("Quantity (e.g. 200g)", text: row.displayQuantity)
                TextField("Grams", text: row.quantityGramsText)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                    .frame(width: numberFieldWidth)
            }
            .font(Tide.caption)
            // Live macro-coverage badge tells the user up-front whether
            // this row will contribute to recipe totals.
            macroCoverageBadge(for: row.wrappedValue)
        }
        .padding(.vertical, Tide.s1)
    }

    private var ingredientsSection: some View {
        Section {
            ForEach($ingredientRows) { $row in
                ingredientRowView(row: $row)
            }
            .onDelete { offsets in
                ingredientRows.remove(atOffsets: offsets)
                if ingredientRows.isEmpty {
                    ingredientRows.append(IngredientRow())
                }
            }
            Button {
                ingredientRows.append(IngredientRow())
            } label: {
                Label("Add Ingredient", systemImage: "plus.circle")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(mood.accent)
                    .frame(minHeight: Tide.hit, alignment: .leading)
            }
        } header: {
            Text("Ingredients").tideLabel()
        } footer: {
            Text(
                "Macros come from a built-in food database when the name matches and grams are filled in. Unknown items still save — they just won't contribute to totals."
            )
            .font(Tide.caption)
            .foregroundStyle(Tide.text3)
        }
        .fuelRow()
    }

    /// Three-state badge under each ingredient row:
    /// - tracked: name is in FoodMacroDatabase AND grams > 0 → row will
    ///   contribute to recipe totals.
    /// - needs grams: name is known but grams field is empty.
    /// - unknown food: name not in DB → user can still save but the row
    ///   contributes zero macros.
    /// Empty name renders nothing so a fresh row doesn't get a warning.
    @ViewBuilder
    private func macroCoverageBadge(for row: IngredientRow) -> some View {
        let trimmed = row.name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            EmptyView()
        } else {
            let inDB = FoodMacroDatabase.lookup(trimmed) != nil
            let grams = Double(row.quantityGramsText.replacingOccurrences(of: ",", with: ".")) ?? 0
            HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                if inDB, grams > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Tide.good)
                    Text("Tracked")
                        .foregroundStyle(Tide.good)
                } else if inDB {
                    Image(systemName: "scalemass")
                        .foregroundStyle(Tide.warn)
                    Text("Add grams to track macros")
                        .foregroundStyle(Tide.warn)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(Tide.text3)
                    Text("Not in food database — saves but excluded from macros")
                        .foregroundStyle(Tide.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(Tide.caption)
        }
    }

    /// Single-step row. Extracted so the index lookup can happen outside
    /// the body builder — keeps the parent ForEach's type-check cheap.
    @ViewBuilder
    private func stepRowView(row: Binding<StepRow>) -> some View {
        let idx = stepRows.firstIndex(where: { $0.id == row.wrappedValue.id }) ?? 0
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Step \(idx + 1)").tideLabel()
            TextField("Instruction", text: row.instruction, axis: .vertical)
                .lineLimit(2 ... 5)
            TextField("Minutes (optional)", text: row.durationText)
                .keyboardType(.numberPad)
                .font(Tide.caption)
        }
        .padding(.vertical, Tide.s1)
    }

    private var stepsSection: some View {
        Section {
            // Iterate by id and look up the row's index separately rather
            // than combining $Binding + enumerated() in one expression —
            // SwiftUI's type-checker times out on the combined form, and
            // splitting it keeps the view-body expressions trivially
            // type-checkable.
            ForEach($stepRows) { $row in
                stepRowView(row: $row)
            }
            .onDelete { offsets in
                stepRows.remove(atOffsets: offsets)
                if stepRows.isEmpty {
                    stepRows.append(StepRow())
                }
            }
            Button {
                stepRows.append(StepRow())
            } label: {
                Label("Add Step", systemImage: "plus.circle")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(mood.accent)
                    .frame(minHeight: Tide.hit, alignment: .leading)
            }
        } header: {
            Text("Steps").tideLabel()
        }
        .fuelRow()
    }

    // MARK: - Save

    private func save() {
        let recipe = Recipe(
            name: trimmedName,
            servings: max(1, Int(servingsText) ?? 2),
            prepMinutes: Int(prepMinutesText),
            cookMinutes: Int(cookMinutesText),
            source: .userCreated
        )

        // Build ingredients with FoodMacroDatabase lookup. Per-ingredient
        // macros let the recipe surface accurate totals without the user
        // typing them manually; recomputeMacroTotals at insert time rolls
        // them into Recipe.totalCalories etc.
        var ingredients: [RecipeIngredient] = []
        for (i, row) in ingredientRows.enumerated() {
            let trimmed = row.name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                continue
            }
            let grams = Double(row.quantityGramsText.replacingOccurrences(of: ",", with: ".")) ?? 0
            let macros = FoodMacroDatabase.lookup(trimmed)
            let scale = grams / 100.0
            ingredients.append(RecipeIngredient(
                recipe: recipe,
                orderIndex: i,
                canonicalFoodName: trimmed.lowercased(),
                displayName: trimmed,
                quantityGrams: grams,
                displayQuantity: row.displayQuantity.isEmpty ? nil : row.displayQuantity,
                calories: macros.map { $0.calories * scale },
                proteinGrams: macros.map { $0.protein * scale },
                carbsGrams: macros.map { $0.carbs * scale },
                fatGrams: macros.map { $0.fat * scale },
                fiberGrams: macros.map { $0.fiber * scale }
            ))
        }
        recipe.ingredients = ingredients

        var steps: [RecipeStep] = []
        for (i, row) in stepRows.enumerated() {
            let trimmed = row.instruction.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                continue
            }
            steps.append(RecipeStep(
                recipe: recipe,
                orderIndex: i,
                instruction: trimmed,
                durationMinutes: Int(row.durationText)
            ))
        }
        recipe.steps = steps

        onSave(recipe)
        dismiss()
    }
}
