//
// VoicePantryEditApplier.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation
import SwiftData

// MARK: - PantryEditApplyResult

/// One applied (or failed) intent, for the confirm-list UI shown before
/// commit and for the post-apply summary.
struct PantryEditApplyResult: Sendable, Equatable {
    let intent: PantryEditIntent
    let summary: String
    let succeeded: Bool
}

// MARK: - VoicePantryEditApplier

/// Applies parsed `PantryEditIntent`s against the pantry. Every matching
/// row for a canonical name is affected (not just the first) — a user
/// rarely tracks WHICH specific carton of milk they mean, so "I'm out of
/// milk" zeroes every milk row, "move the chicken to the freezer" moves
/// every chicken row, etc.
@MainActor
enum VoicePantryEditApplier {
    @discardableResult
    static func apply(
        _ intents: [PantryEditIntent],
        pantryService: any PantryServiceProtocol,
        modelContext: ModelContext
    ) -> [PantryEditApplyResult] {
        intents.map { apply($0, pantryService: pantryService, modelContext: modelContext) }
    }

    private static func matchingRows(canonical: String, pantryService: any PantryServiceProtocol) -> [PantryItem] {
        let all = (try? pantryService.fetchAll()) ?? []
        return all.filter { $0.canonicalName == canonical && $0.quantity > 0 }
            .sorted { lhs, rhs in
                switch (lhs.useBy, rhs.useBy) {
                case let (l?, r?): l < r
                case (nil, nil): false
                case (nil, _): false
                case (_, nil): true
                }
            }
    }

    private static func apply(
        _ intent: PantryEditIntent,
        pantryService: any PantryServiceProtocol,
        modelContext: ModelContext
    ) -> PantryEditApplyResult {
        switch intent {
        case let .markDepleted(rawName):
            let canonical = FoodCanonicalizer.canonicalize(rawName)
            let display = FoodCanonicalizer.displayName(rawName)
            let label = display.isEmpty ? rawName.capitalized : display
            let rows = matchingRows(canonical: canonical, pantryService: pantryService)
            for row in rows {
                _ = try? pantryService.updateItem(
                    row, quantity: 0, unit: nil, storageLocation: nil, useBy: nil, brand: nil
                )
            }
            let addedToList = (try? PantryGroceryBridge.addToCurrentGroceryList(
                canonicalName: canonical, displayName: label, quantity: 1, unit: .pieces, modelContext: modelContext
            )) != nil
            let summary = addedToList
                ? "\(label) marked out — added to grocery list"
                : "\(label) marked out"
            return PantryEditApplyResult(intent: intent, summary: summary, succeeded: true)

        case let .decrement(rawName, fraction):
            let canonical = FoodCanonicalizer.canonicalize(rawName)
            let display = FoodCanonicalizer.displayName(rawName)
            let label = display.isEmpty ? rawName.capitalized : display
            let rows = matchingRows(canonical: canonical, pantryService: pantryService)
            guard !rows.isEmpty else {
                return PantryEditApplyResult(intent: intent, summary: "Couldn't find \(label) in your pantry", succeeded: false)
            }
            let clampedFraction = min(max(fraction, 0), 1)
            let totalQuantity = rows.reduce(0.0) { $0 + $1.quantity }
            var remainingToRemove = totalQuantity * clampedFraction
            for row in rows {
                guard remainingToRemove > 0 else {
                    break
                }
                let consume = min(row.quantity, remainingToRemove)
                _ = try? pantryService.updateItem(
                    row, quantity: row.quantity - consume, unit: nil, storageLocation: nil, useBy: nil, brand: nil
                )
                remainingToRemove -= consume
            }
            let summary = clampedFraction >= 1
                ? "Used up \(label)"
                : "Used some \(label)"
            return PantryEditApplyResult(intent: intent, summary: summary, succeeded: true)

        case let .move(rawName, location):
            let canonical = FoodCanonicalizer.canonicalize(rawName)
            let display = FoodCanonicalizer.displayName(rawName)
            let label = display.isEmpty ? rawName.capitalized : display
            let rows = matchingRows(canonical: canonical, pantryService: pantryService)
            guard !rows.isEmpty else {
                return PantryEditApplyResult(intent: intent, summary: "Couldn't find \(label) in your pantry", succeeded: false)
            }
            for row in rows {
                _ = try? pantryService.updateItem(
                    row, quantity: nil, unit: nil, storageLocation: location, useBy: nil, brand: nil
                )
            }
            return PantryEditApplyResult(intent: intent, summary: "Moved \(label) to the \(location.rawValue)", succeeded: true)

        case let .discard(rawName):
            let canonical = FoodCanonicalizer.canonicalize(rawName)
            let display = FoodCanonicalizer.displayName(rawName)
            let label = display.isEmpty ? rawName.capitalized : display
            let rows = matchingRows(canonical: canonical, pantryService: pantryService)
            guard !rows.isEmpty else {
                return PantryEditApplyResult(intent: intent, summary: "Couldn't find \(label) in your pantry", succeeded: false)
            }
            for row in rows {
                _ = try? pantryService.archive(row)
            }
            return PantryEditApplyResult(intent: intent, summary: "Threw out \(label)", succeeded: true)
        }
    }
}
