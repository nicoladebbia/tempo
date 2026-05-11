//
// LocalRecipeService.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import os
import SwiftData

// MARK: - LocalRecipeService

@MainActor
@Observable
final class LocalRecipeService: RecipeServiceProtocol {
    private let modelContext: ModelContext
    private let logger = Logger.nutrition

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD

    func fetchAll() throws -> [Recipe] {
        var descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> { recipe in
                recipe.isArchived == false
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        return try modelContext.fetch(descriptor)
    }

    func fetchFavorites() throws -> [Recipe] {
        var descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> { recipe in
                recipe.isArchived == false && recipe.isFavorite == true
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        return try modelContext.fetch(descriptor)
    }

    func fetch(byID id: UUID) throws -> Recipe? {
        var descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func add(_ recipe: Recipe) throws {
        modelContext.insert(recipe)
        recipe.recomputeMacroTotals()
        try modelContext.save()
    }

    func update(_ recipe: Recipe) throws {
        recipe.recomputeMacroTotals()
        recipe.updatedAt = Date()
        try modelContext.save()
    }

    func delete(_ recipe: Recipe) throws {
        modelContext.delete(recipe)
        try modelContext.save()
    }

    func toggleFavorite(_ recipe: Recipe) throws {
        recipe.isFavorite.toggle()
        recipe.updatedAt = Date()
        try modelContext.save()
    }

    // MARK: - Suggestions

    func suggest(inputs: RecipeSuggestionInputs, limit: Int = 10) throws -> [RecipeSuggestion] {
        let candidates = try fetchAll()
        let suggestions = RecipeSuggestionEngine.rank(candidates: candidates, inputs: inputs, limit: limit)
        logger.info("Recipe suggestion: \(candidates.count) candidates → \(suggestions.count) suggestions")
        return suggestions
    }
}

// MARK: - MockRecipeService

@MainActor
@Observable
final class MockRecipeService: RecipeServiceProtocol {
    private(set) var recipes: [Recipe]

    init(recipes: [Recipe] = []) {
        self.recipes = recipes
    }

    func fetchAll() throws -> [Recipe] {
        recipes.filter { !$0.isArchived }
    }

    func fetchFavorites() throws -> [Recipe] {
        recipes.filter { !$0.isArchived && $0.isFavorite }
    }

    func fetch(byID id: UUID) throws -> Recipe? {
        recipes.first { $0.id == id }
    }

    func add(_ recipe: Recipe) throws {
        recipe.recomputeMacroTotals()
        recipes.append(recipe)
    }

    func update(_ recipe: Recipe) throws {
        recipe.recomputeMacroTotals()
        recipe.updatedAt = Date()
    }

    func delete(_ recipe: Recipe) throws {
        recipes.removeAll { $0.id == recipe.id }
    }

    func toggleFavorite(_ recipe: Recipe) throws {
        recipe.isFavorite.toggle()
    }

    func suggest(inputs: RecipeSuggestionInputs, limit: Int = 10) throws -> [RecipeSuggestion] {
        try RecipeSuggestionEngine.rank(candidates: fetchAll(), inputs: inputs, limit: limit)
    }
}
