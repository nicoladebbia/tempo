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
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
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
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.lg)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Recipes")
        .toolbar {
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
                    Divider()
                    Button {
                        viewModel.refreshRecipeSuggestions()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
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
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                Text(suggestion.recipeName)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                coverageBadge(suggestion)
            }
            HStack(spacing: TempoSpacing.sm) {
                if !suggestion.missingIngredients.isEmpty {
                    Label("Missing \(suggestion.missingIngredients.count)", systemImage: "minus.circle")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoWarning)
                } else {
                    Label("Have everything", systemImage: "checkmark.circle.fill")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoSuccess)
                }
                Spacer()
                Text("Macro fit \(Int(suggestion.macroAlignmentScore * 100))%")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            if !suggestion.missingIngredients.isEmpty {
                Text(suggestion.missingIngredients.joined(separator: ", "))
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .lineLimit(2)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func coverageBadge(_ suggestion: RecipeSuggestion) -> some View {
        let pct = Int(suggestion.coverageScore * 100)
        let color: Color = suggestion.coverageScore >= 0.9
            ? .tempoSuccess
            : (suggestion.coverageScore >= 0.6 ? .tempoWarning : .tempoError)
        return Text("\(pct)%")
            .font(.tempoCaption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 40))
                .foregroundStyle(Color.tempoTextTertiary)
            Text("No recipe matches yet")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("Add items to your pantry — or save a recipe — and we'll rank what you can make.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xxxl)
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
            }
        }
        .task {
            recipe = try? viewModel.recipeService?.fetch(byID: recipeID)
        }
    }
}

// MARK: - RecipeDetailView

struct RecipeDetailView: View {
    let recipe: Recipe

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                heroCard
                ingredientsSection
                stepsSection
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.lg)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            if let description = recipe.recipeDescription, !description.isEmpty {
                Text(description)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            HStack(spacing: TempoSpacing.md) {
                metaTag(systemImage: "clock", text: "\(recipe.totalMinutes) min")
                metaTag(systemImage: "person.2", text: "\(recipe.servings) servings")
                metaTag(systemImage: "flame", text: "\(Int(recipe.totalCalories)) kcal")
            }
            HStack(spacing: TempoSpacing.md) {
                macroChip(label: "P", value: recipe.totalProteinGrams)
                macroChip(label: "C", value: recipe.totalCarbsGrams)
                macroChip(label: "F", value: recipe.totalFatGrams)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("INGREDIENTS")
                .font(.tempoModuleTag)
                .foregroundStyle(Color.tempoTextSecondary)
            ForEach(recipe.orderedIngredients, id: \.id) { ing in
                HStack {
                    Image(systemName: ing.isOptional ? "circle.dashed" : "circle")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text(ing.displayName)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Spacer()
                    Text("\(Int(ing.quantityGrams))g")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("STEPS")
                .font(.tempoModuleTag)
                .foregroundStyle(Color.tempoTextSecondary)
            ForEach(Array(recipe.orderedSteps.enumerated()), id: \.element.id) { idx, step in
                HStack(alignment: .top, spacing: TempoSpacing.sm) {
                    Text("\(idx + 1).")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoSignal)
                        .frame(width: 24, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.instruction)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                        if let mins = step.durationMinutes {
                            Text("\(mins) min")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func metaTag(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoTextSecondary)
    }

    private func macroChip(label: String, value: Double) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            Text("\(Int(value))g")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }
}
