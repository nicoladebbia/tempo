//
// RecipeSuggestionsView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - RecipeSuggestionsView

struct RecipeSuggestionsView: View {
    @Bindable
    var viewModel: NutritionTabViewModel

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    /// Presented when the user taps "Write Recipe" — typed form.
    @State
    private var showWriteRecipe = false

    /// Presented when the user taps "Tell AI" — NL textarea + Haiku parse.
    @State
    private var showTellAIRecipe = false

    /// Toast surfaced after a successful save so the user gets a beat of
    /// confirmation before navigating into their new recipe.
    @State
    private var savedRecipeToast: ToastData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s3) {
                if viewModel.recipeState.suggestions.isEmpty, !viewModel.recipeState.isLoading {
                    emptyState
                } else {
                    ForEach(viewModel.recipeState.suggestions) { suggestion in
                        NavigationLink {
                            RecipeDetailLoader(
                                recipeID: suggestion.recipeID,
                                viewModel: viewModel
                            )
                        } label: {
                            suggestionCard(suggestion)
                        }
                        .buttonStyle(FuelPressStyle())
                    }
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .tidePage()
        .navigationTitle("Recipes")
        .toolbar {
            // Refresh stays as a one-tap action (it's the most common one
            // — pantry changes daily, the suggestions list updates often).
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.refreshRecipeSuggestions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
            // Add lives under a separate "+" so the two creation paths
            // (typed form vs AI dictation) share a single chooser without
            // burying refresh under it.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showWriteRecipe = true
                    } label: {
                        Label("Write Recipe", systemImage: "square.and.pencil")
                    }
                    Button {
                        showTellAIRecipe = true
                    } label: {
                        Label("Tell AI", systemImage: "wand.and.stars")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add recipe")
            }
        }
        .tideCovered(showWriteRecipe || showTellAIRecipe)
        .sheet(isPresented: $showWriteRecipe) {
            WriteRecipeView { recipe in
                saveCustomRecipe(recipe)
            }
        }
        .sheet(isPresented: $showTellAIRecipe) {
            TellAIRecipeView(apiClient: services.apiClient) { recipe in
                saveCustomRecipe(recipe)
            }
        }
        .tempoToast($savedRecipeToast)
        .task {
            viewModel.attachPhase7Services(modelContext: modelContext, services: services)
            viewModel.refreshRecipeSuggestions()
        }
    }

    /// Persist a user-created Recipe through LocalRecipeService (the
    /// existing service that owns Recipe insertion + macro recompute), then
    /// refresh suggestions so the new recipe shows up immediately.
    @MainActor
    private func saveCustomRecipe(_ recipe: Recipe) {
        do {
            let service = LocalRecipeService(modelContext: modelContext)
            try service.add(recipe)
            savedRecipeToast = ToastData(
                message: "Saved “\(recipe.name)”",
                style: .success
            )
            HapticManager.notification(.success)
            viewModel.refreshRecipeSuggestions()
        } catch {
            savedRecipeToast = ToastData(
                message: "Couldn't save: \(error.localizedDescription)",
                style: .error
            )
        }
    }

    // MARK: - Sections

    private func suggestionCard(_ suggestion: RecipeSuggestion) -> some View {
        let tone = coverageTone(suggestion)
        return VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text(suggestion.recipeName)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Tide.s2)
                FuelPill(text: "\(Int(suggestion.coverageScore * 100))%", color: tone)
                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }

            TideLevelBar(progress: min(max(suggestion.coverageScore, 0), 1), color: tone, height: Tide.barSlim)

            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                if !suggestion.missingIngredients.isEmpty {
                    Label("Missing \(suggestion.missingIngredients.count)", systemImage: "minus.circle")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.warn)
                } else {
                    Label("Have everything", systemImage: "checkmark.circle.fill")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.good)
                }
                Spacer(minLength: Tide.s2)
                Text("Macro fit \(Int(suggestion.macroAlignmentScore * 100))%")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .monospacedDigit()
            }

            if !suggestion.missingIngredients.isEmpty {
                Text(suggestion.missingIngredients.joined(separator: ", "))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .contentShape(.rect(cornerRadius: Tide.tileRadius))
    }

    /// Green when the pantry covers nearly everything, amber when it covers
    /// most of it, red when a lot is missing.
    private func coverageTone(_ suggestion: RecipeSuggestion) -> Color {
        suggestion.coverageScore >= 0.9
            ? Tide.good
            : (suggestion.coverageScore >= 0.6 ? Tide.warn : Tide.danger)
    }

    private var emptyState: some View {
        FuelEmptyState(
            icon: "fork.knife.circle",
            title: "No recipe matches yet",
            message: "Add items to your pantry — or save a recipe — and we'll rank what you can make."
        )
        .padding(.top, Tide.s6)
    }
}

// MARK: - RecipeDetailLoader

/// Resolves a recipe by ID before showing the detail view. Pure UI; the
/// suggestion only carries the ID + summary fields, so we load the full
/// model on demand.
struct RecipeDetailLoader: View {
    let recipeID: UUID
    @Bindable
    var viewModel: NutritionTabViewModel

    @State
    private var recipe: Recipe?

    var body: some View {
        Group {
            if let recipe {
                RecipeDetailView(recipe: recipe)
            } else {
                ProgressView()
                    .tint(Tide.text)
            }
        }
        .tidePage()
        .task {
            recipe = try? viewModel.recipeService?.fetch(byID: recipeID)
        }
    }
}

// MARK: - RecipeDetailView

struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s4) {
                heroCard
                ingredientsSection
                stepsSection
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .tidePage()
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            if let description = recipe.recipeDescription, !description.isEmpty {
                Text(description)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TideNumber("\(Int(recipe.totalCalories))", unit: "kcal", size: Tide.numeralM)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s4) {
                    metaTag(systemImage: "clock", text: "\(recipe.totalMinutes) min")
                    metaTag(systemImage: "person.2", text: "\(recipe.servings) servings")
                }
                VStack(alignment: .leading, spacing: Tide.s2) {
                    metaTag(systemImage: "clock", text: "\(recipe.totalMinutes) min")
                    metaTag(systemImage: "person.2", text: "\(recipe.servings) servings")
                }
            }
            FuelMacroInline(
                protein: Int(recipe.totalProteinGrams),
                carbs: Int(recipe.totalCarbsGrams),
                fat: Int(recipe.totalFatGrams)
            )
        }
        .tideCard()
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Ingredients").tideLabel()
            ForEach(recipe.orderedIngredients, id: \.id) { ing in
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Image(systemName: ing.isOptional ? "circle.dashed" : "circle")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)
                    Text(ing.displayName)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Tide.s2)
                    Text("\(Int(ing.quantityGrams))g")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .monospacedDigit()
                }
            }
        }
        .tideCard()
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Steps").tideLabel()
            ForEach(Array(recipe.orderedSteps.enumerated()), id: \.element.id) { idx, step in
                HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                    Text("\(idx + 1)")
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
                        if let mins = step.durationMinutes {
                            Text("\(mins) min")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .tideCard()
    }

    private func metaTag(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(Tide.caption)
            .foregroundStyle(Tide.text2)
    }
}
