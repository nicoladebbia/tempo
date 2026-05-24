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

    @State private var name: String = ""
    @State private var servingsText: String = "2"
    @State private var prepMinutesText: String = ""
    @State private var cookMinutesText: String = ""
    @State private var ingredientRows: [IngredientRow] = [IngredientRow()]
    @State private var stepRows: [StepRow] = [StepRow()]

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
            .navigationTitle("Write Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Sections

    private var basicsSection: some View {
        Section("Basics") {
            TextField("Recipe name", text: $name)
            HStack {
                Text("Servings")
                Spacer()
                TextField("2", text: $servingsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
            HStack {
                Text("Prep time (min)")
                Spacer()
                TextField("optional", text: $prepMinutesText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            HStack {
                Text("Cook time (min)")
                Spacer()
                TextField("optional", text: $cookMinutesText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach($ingredientRows) { $row in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Ingredient (e.g. chicken breast)", text: $row.name)
                        .textInputAutocapitalization(.never)
                    HStack {
                        TextField("Quantity (e.g. 200g)", text: $row.displayQuantity)
                        TextField("Grams", text: $row.quantityGramsText)
                            .keyboardType(.decimalPad)
                            .frame(width: 70)
                    }
                    .font(.tempoCaption1)
                    // Live macro-coverage badge. Tells the user up-front
                    // whether this row will contribute to recipe totals.
                    // Previously you'd save a recipe with "homemade
                    // soffritto" (not in DB, no grams) and discover later
                    // that totals were nonsense — this surfaces the gap
                    // while you can still fix it.
                    macroCoverageBadge(for: row)
                }
                .padding(.vertical, 4)
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
            }
        } header: {
            Text("Ingredients")
        } footer: {
            Text("Macros come from a built-in food database when the name matches and grams are filled in. Unknown items still save — they just won't contribute to totals.")
                .font(.tempoCaption2)
        }
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
            HStack(spacing: 4) {
                if inDB, grams > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.tempoSuccess)
                    Text("Tracked")
                        .foregroundStyle(Color.tempoSuccess)
                } else if inDB {
                    Image(systemName: "scalemass")
                        .foregroundStyle(Color.tempoWarning)
                    Text("Add grams to track macros")
                        .foregroundStyle(Color.tempoWarning)
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text("Not in food database — saves but excluded from macros")
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .font(.tempoCaption2)
        }
    }

    private var stepsSection: some View {
        Section("Steps") {
            ForEach(Array($stepRows.enumerated()), id: \.element.id) { index, $row in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step \(index + 1)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    TextField("Instruction", text: $row.instruction, axis: .vertical)
                        .lineLimit(2 ... 5)
                    TextField("Minutes (optional)", text: $row.durationText)
                        .keyboardType(.numberPad)
                        .font(.tempoCaption1)
                }
                .padding(.vertical, 4)
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
            }
        }
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
            guard !trimmed.isEmpty else { continue }
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
            guard !trimmed.isEmpty else { continue }
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
