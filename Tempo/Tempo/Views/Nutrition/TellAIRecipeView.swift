//
// TellAIRecipeView.swift
// Tempo
//
// Natural-language recipe creation: the user types or dictates a free-text
// recipe ("Pasta carbonara — 200g spaghetti, 100g pancetta, 2 eggs,
// parmesan, pepper. Boil pasta 10 min, render pancetta, toss with egg +
// cheese off heat") and Haiku parses it into a structured Recipe with
// ordered ingredients + steps. The parsed result lands in a confirmation
// sheet (WriteRecipeView's preview pattern would be nice but lift later —
// for now we save directly on Parse-and-Save).
//

import SwiftUI

struct TellAIRecipeView: View {
    let apiClient: APIClient
    var onSave: (Recipe) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var text: String = ""
    @State private var service: RecipeParserService?
    @State private var isParsing: Bool = false
    @State private var errorText: String?

    /// Parsed recipe awaiting user confirmation. Non-nil → preview sheet
    /// is presented. The user must accept (or edit) before persistence,
    /// matching the ParsedFoodReviewSheet pattern in NL meal logging.
    @State private var pendingRecipe: Recipe?

    @FocusState
    private var textFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                Text("Describe your recipe — ingredients with amounts, then steps. The AI will structure it.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .padding(.horizontal, TempoSpacing.screenEdge)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .padding(.horizontal, TempoSpacing.md + 4)
                            .padding(.vertical, TempoSpacing.md + 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, TempoSpacing.md)
                        .padding(.vertical, TempoSpacing.md)
                        .focused($textFocused)
                        .disabled(isParsing)
                }
                .frame(minHeight: 220)
                .background(Color.tempoBgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                        .stroke(Color.tempoBorder, lineWidth: 1)
                )
                .padding(.horizontal, TempoSpacing.screenEdge)

                if let errorText {
                    Text(errorText)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                        .padding(.horizontal, TempoSpacing.screenEdge)
                }

                Spacer()
            }
            .padding(.vertical, TempoSpacing.lg)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Tell AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isParsing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await parseAndPreview() }
                    } label: {
                        if isParsing {
                            ProgressView()
                        } else {
                            Text("Parse")
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isParsing)
                }
            }
            .onAppear { textFocused = true }
            // After parsing, present a preview so the user can audit what
            // Haiku produced before it lands in the DB. Save fires onSave
            // upstream then dismisses both sheets; Discard just clears the
            // pending recipe (the text the user typed is preserved so they
            // can retry).
            .sheet(item: $pendingRecipe) { recipe in
                RecipePreviewSheet(
                    recipe: recipe,
                    onConfirm: { confirmed in
                        onSave(confirmed)
                        pendingRecipe = nil
                        dismiss()
                    },
                    onCancel: {
                        pendingRecipe = nil
                    }
                )
            }
        }
    }

    private var placeholder: String {
        """
        Pasta carbonara, serves 2.
        Ingredients: 200g spaghetti, 100g pancetta, 2 eggs, 40g pecorino, pepper.
        Steps: Boil pasta 10 min. Render pancetta crisp, ~6 min. Whisk eggs + pecorino. Drain pasta, toss off heat with pancetta + egg sauce. Finish with cracked pepper.
        """
    }

    @MainActor
    private func parseAndPreview() async {
        guard !isParsing else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        textFocused = false
        isParsing = true
        errorText = nil
        defer { isParsing = false }

        let svc = service ?? RecipeParserService(apiClient: apiClient)
        service = svc
        do {
            let recipe = try await svc.parse(trimmed)
            // Guard against degenerate parses — Haiku can return empty
            // name / no ingredients on garbled input. Without this we'd
            // happily persist garbage and surface a useless row in the
            // Recipes list.
            let trimmedName = recipe.name.trimmingCharacters(in: .whitespaces)
            let ingredientCount = recipe.ingredients?.count ?? 0
            guard !trimmedName.isEmpty, ingredientCount > 0 else {
                errorText = "AI couldn't pull a usable recipe from that. Try being more specific about ingredients and steps."
                HapticManager.notification(.error)
                return
            }
            pendingRecipe = recipe
        } catch {
            errorText = (error as? RecipeParseError)?.errorDescription
                ?? error.localizedDescription
            HapticManager.notification(.error)
        }
    }
}

// MARK: - RecipePreviewSheet

/// User-facing confirmation between Haiku parsing and DB persistence.
/// Shows the parsed recipe (name, servings, prep/cook time, ingredients,
/// steps) so the user can audit what the AI produced before it's saved.
/// Tap Save → onConfirm fires with the recipe. Cancel discards.
private struct RecipePreviewSheet: View {
    let recipe: Recipe
    let onConfirm: (Recipe) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    header
                    ingredientsBlock
                    stepsBlock
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onConfirm(recipe)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text(recipe.name)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            HStack(spacing: TempoSpacing.md) {
                Label("\(recipe.servings) servings", systemImage: "fork.knife")
                if let prep = recipe.prepMinutes, prep > 0 {
                    Label("\(prep) min prep", systemImage: "timer")
                }
                if let cook = recipe.cookMinutes, cook > 0 {
                    Label("\(cook) min cook", systemImage: "flame")
                }
            }
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    private var ingredientsBlock: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("INGREDIENTS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            VStack(spacing: TempoSpacing.xs) {
                ForEach(recipe.orderedIngredients) { ing in
                    HStack(alignment: .firstTextBaseline) {
                        Text(ing.displayName)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        Text(ing.displayQuantity ?? "\(Int(ing.quantityGrams))g")
                            .font(.tempoCaption1.monospacedDigit())
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    .padding(.horizontal, TempoSpacing.md)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.tempoBgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sm, style: .continuous))
                }
            }
        }
    }

    private var stepsBlock: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("STEPS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                ForEach(Array(recipe.orderedSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: TempoSpacing.sm) {
                        Text("\(index + 1)")
                            .font(.tempoCaption1.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.tempoSignal)
                            .frame(width: 20, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.instruction)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let min = step.durationMinutes, min > 0 {
                                Text("~\(min) min")
                                    .font(.tempoCaption2)
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }
                        }
                    }
                }
            }
        }
    }
}
