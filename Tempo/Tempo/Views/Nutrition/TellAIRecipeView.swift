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

// MARK: - TellAIRecipeView

struct TellAIRecipeView: View {
    let apiClient: APIClient
    var onSave: (Recipe) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var text: String = ""
    @State private var service: RecipeParserService?
    @State private var isParsing: Bool = false
    @State private var errorText: String?
    /// The reply came back but held no usable recipe (vs. the call failing).
    @State private var resultWasEmpty = false
    @State private var blocker: AIBlocker?

    /// Parsed recipe awaiting user confirmation. Non-nil → preview sheet
    /// is presented. The user must accept (or edit) before persistence,
    /// matching the ParsedFoodReviewSheet pattern in NL meal logging.
    @State private var pendingRecipe: Recipe?

    @FocusState
    private var textFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    Text("Describe your recipe — ingredients with amounts, then steps. The AI will structure it.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)

                    editor

                    if isParsing {
                        FuelAIState(kind: .working("Reading your recipe…"))
                            .transition(.opacity)
                    } else if let blocker {
                        AIBlockerCard(blocker: blocker) {
                            self.blocker = nil
                            Task { await parseAndPreview() }
                        }
                    } else if let errorText {
                        if resultWasEmpty {
                            FuelAIState(
                                kind: .empty(title: "No recipe found", message: errorText),
                                actionTitle: "Try again",
                                action: { Task { await parseAndPreview() } }
                            )
                        } else {
                            FuelAIState(
                                kind: .failed(title: "Couldn't read that", message: errorText),
                                actionTitle: "Try again",
                                action: { Task { await parseAndPreview() } }
                            )
                        }
                    }
                }
                .animation(Tide.settle, value: isParsing)
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s4)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .top)
            // The one action sits under the thumb.
            .fuelBottomBar {
                Button("Parse") { Task { await parseAndPreview() } }
                    .buttonStyle(.tidePrimary)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isParsing)
            }
            .tidePage()
            .navigationTitle("Tell AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isParsing)
                }
            }
            .onAppear { textFocused = true }
            .tideCovered(pendingRecipe != nil)
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

    /// The free-text box: a soft-filled field with the example as its placeholder.
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text3)
                    .padding(.horizontal, Tide.s4)
                    .padding(.vertical, Tide.s5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Tide.s3)
                .padding(.vertical, Tide.s3)
                .focused($textFocused)
                .disabled(isParsing)
        }
        .frame(minHeight: Tide.fuelEditor)
        .background(Tide.fill, in: .rect(cornerRadius: Tide.tileRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                .stroke(Tide.hairline, lineWidth: 1)
        )
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
        guard !isParsing else {
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }
        textFocused = false
        isParsing = true
        errorText = nil
        resultWasEmpty = false
        blocker = nil
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
                resultWasEmpty = true
                HapticManager.notification(.error)
                return
            }
            pendingRecipe = recipe
        } catch {
            blocker = AIBlocker(error)
            errorText = AIBlocker.message(for: error)
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
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    header
                    ingredientsBlock
                    stepsBlock
                }
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s4)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .tidePage()
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        onCancel()
                        dismiss()
                    }
                }
            }
            // The one action sits under the thumb.
            .fuelBottomBar {
                Button("Save") {
                    onConfirm(recipe)
                    dismiss()
                }
                .buttonStyle(.tidePrimary)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text(recipe.name)
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s4) { metaLabels }
                VStack(alignment: .leading, spacing: Tide.s1) { metaLabels }
            }
            .font(Tide.caption)
            .foregroundStyle(Tide.text2)
        }
    }

    @ViewBuilder
    private var metaLabels: some View {
        Label(FuelWords.count(recipe.servings, "serving"), systemImage: "fork.knife")
        if let prep = recipe.prepMinutes, prep > 0 {
            Label("\(prep) min prep", systemImage: "timer")
        }
        if let cook = recipe.cookMinutes, cook > 0 {
            Label("\(cook) min cook", systemImage: "flame")
        }
    }

    private var ingredientsBlock: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Ingredients").tideLabel()
            VStack(spacing: 0) {
                ForEach(recipe.orderedIngredients) { ing in
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                        Text(ing.displayName)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Tide.s2)
                        Text(ing.displayQuantity ?? "\(Int(ing.quantityGrams))g")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .monospacedDigit()
                    }
                    .padding(.vertical, Tide.s2)
                    .frame(minHeight: Tide.hit)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if ing.id != recipe.orderedIngredients.last?.id {
                        Divider().overlay(Tide.hairline)
                    }
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private var stepsBlock: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Steps").tideLabel()
            VStack(alignment: .leading, spacing: Tide.s3) {
                ForEach(Array(recipe.orderedSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                        Text("\(index + 1)")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(mood.accent)
                            .monospacedDigit()
                            .frame(width: Tide.s5, alignment: .leading)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Tide.hair) {
                            Text(step.instruction)
                                .font(Tide.body)
                                .foregroundStyle(Tide.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if let min = step.durationMinutes, min > 0 {
                                Text("~\(min) min")
                                    .font(Tide.caption)
                                    .foregroundStyle(Tide.text3)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }
}
