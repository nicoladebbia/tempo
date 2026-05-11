//
// RecipeServiceProtocol.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftData

@MainActor
protocol RecipeServiceProtocol: Sendable {
    func fetchAll() throws -> [Recipe]
    func fetchFavorites() throws -> [Recipe]
    func fetch(byID id: UUID) throws -> Recipe?
    func add(_ recipe: Recipe) throws
    func update(_ recipe: Recipe) throws
    func delete(_ recipe: Recipe) throws
    func toggleFavorite(_ recipe: Recipe) throws

    /// Rank pantry-compatible recipes. Returns the top `limit` suggestions.
    func suggest(inputs: RecipeSuggestionInputs, limit: Int) throws -> [RecipeSuggestion]
}
