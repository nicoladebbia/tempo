//
// PantryDecrementService.swift
// Tempo
//
// Created by Tempo on 14/05/2026.
//

import Foundation
import os
import SwiftData

// MARK: - PantryDecrementDetail

/// One row's exact contribution to a decrement — recorded on the meal
/// (`PlannedMeal.decrementDetail`) so an undo can credit back EXACTLY what
/// was taken, from EXACTLY the row it came from, instead of the old
/// approximate "re-derive from the recipe" inverse.
struct PantryDecrementDetail: Codable, Sendable, Equatable {
    let pantryItemID: UUID
    let canonicalName: String
    let unitRaw: String
    /// Amount applied, in the pantry item's OWN unit, always positive.
    let amount: Double
}

// MARK: - PantryDecrementResult

/// Per-ingredient outcome of a pantry decrement. Callers can surface a
/// banner when items hit zero ("you're out of rolled oats — added to
/// grocery list") or roll up totals for telemetry.
struct PantryDecrementResult: Sendable {
    enum Outcome: Sendable {
        case decremented(remaining: Double)
        case depleted
        case notFound
        case skippedStaple
        case skippedNoUnitMatch
    }

    let canonicalName: String
    let requestedGrams: Double
    let outcome: Outcome
    /// Per-row amounts actually applied — FIFO across brand-duplicate rows,
    /// earliest `useBy` first. Empty for `.notFound` / `.skipped*` outcomes.
    var details: [PantryDecrementDetail] = []
}

// MARK: - PantryDecrementService

/// Subtracts a meal's ingredients from the pantry the moment the user
/// marks it eaten. Honest about its limits:
///   - Staples (salt, olive oil, etc.) are skipped — flagged EITHER in
///     `FoodMacroDatabase.naturalPortions` with `isStaple == true`, OR
///     tracked in the user's own `PantryStaple` list (Pantry Smarts).
///   - When several pantry ROWS share a canonical name (brand duplicates,
///     or the same food re-bought before the old batch ran out), the
///     oldest `useBy` is consumed FIRST (FIFO) before moving to the next
///     row — matches how food actually spoils.
///   - Pantry items stored in `.grams` / `.kilograms` / `.milliliters` /
///     `.liters` are decremented directly with unit normalization.
///   - Pantry items stored in `.pieces` are decremented using the
///     natural-portion grams-per-piece (180g carrots ÷ 65g/medium = 2.77
///     pieces).
///   - Container/count units are tracked in FRACTIONS: eating 100 g from a
///     500 g pack leaves 0.8 pack, not an emptied pack. A row is only
///     "depleted" once it falls to `PantryUnit.depletedThreshold` (~0.05
///     unit); that dust is consumed with the last bite so the recorded
///     detail still round-trips exactly on undo.
///   - `.ounces` / `.pounds` are converted by mass (28.35 g / 453.59 g).
///   - `.servings` use the natural-portion grams as one serving; foods
///     without a natural portion are skipped (`skippedNoUnitMatch`).
///   - A meal with NO recipe (a logged substitute) decrements using
///     `meal.foods` directly.
///
/// Callers should NOT invoke this when the user logged a substitute
/// ("ate something else") — in that case the planned ingredients weren't
/// consumed.
@MainActor
enum PantryDecrementService {
    private static let logger = Logger(subsystem: "app.tempo", category: "PantryDecrement")

    /// Decrement pantry for every required ingredient of `meal`. Falls back
    /// to `meal.foods` when the meal has no recipe (a logged substitute or
    /// an ad-hoc log) — the old behavior silently decremented NOTHING for
    /// such meals. Returns per-ingredient outcomes so the caller can surface
    /// user-facing banners (e.g. "out of rolled oats") AND persist
    /// `result.details` onto `meal.decrementDetail` for an exact undo.
    @discardableResult
    static func decrement(
        for meal: PlannedMeal,
        modelContext: ModelContext
    ) -> [PantryDecrementResult] {
        let pairs: [(String, Double)] = if let ingredients = meal.recipe?.ingredients, !ingredients.isEmpty {
            ingredients
                .filter { !$0.isOptional }
                .map { ($0.canonicalFoodName, $0.quantityGrams) }
        } else {
            meal.foods.map { ($0.name, $0.quantityGrams) }
        }
        return decrement(pairs: pairs, label: meal.mealName, modelContext: modelContext)
    }

    /// Decrement the pantry by an arbitrary list of foods — used when a meal
    /// was SUBSTITUTED (recipe cleared, actual foods in `meal.foods`) and the
    /// user confirms they used pantry stock. Same per-item logic as the
    /// recipe path (staple-skip, FIFO, unit conversion, floor at zero).
    @discardableResult
    static func decrement(
        foods: [PlannedFood],
        label: String,
        modelContext: ModelContext
    ) -> [PantryDecrementResult] {
        let pairs = foods.map { ($0.name, $0.quantityGrams) }
        return decrement(pairs: pairs, label: label, modelContext: modelContext)
    }

    /// EXACT inverse of a recorded decrement: credits back precisely the
    /// per-row amounts in `details`, matched by `pantryItemID` — no
    /// re-derivation, no drift. Rows that were deleted/archived since are
    /// skipped (nothing sensible to credit back to).
    @discardableResult
    static func creditExact(
        details: [PantryDecrementDetail],
        modelContext: ModelContext
    ) -> Int {
        guard !details.isEmpty else {
            return 0
        }
        var credited = 0
        for detail in details {
            let id = detail.pantryItemID
            var descriptor = FetchDescriptor<PantryItem>(
                predicate: #Predicate<PantryItem> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            guard let item = (try? modelContext.fetch(descriptor))?.first else {
                continue
            }
            // The row's unit can change between decrement and undo (the
            // tap-edit sheet lets the user re-unit a row at any time).
            // `detail.amount` was recorded in whatever unit the row had AT
            // DECREMENT TIME — crediting it back blindly into a row that's
            // since switched units would silently corrupt the quantity
            // (e.g. crediting 200 straight into a row now in kilograms
            // instead of grams). Convert through grams when they differ.
            if item.unitRaw == detail.unitRaw {
                item.quantity = clean(item.quantity + detail.amount)
            } else if let detailUnit = PantryUnit(rawValue: detail.unitRaw),
                      let grams = gramsEquivalent(pantryAmount: detail.amount, canonicalName: detail.canonicalName, unit: detailUnit),
                      let converted = convertGramsToPantryUnit(grams: grams, canonicalName: detail.canonicalName, unit: item.unit)
            {
                item.quantity = clean(item.quantity + converted)
            } else {
                // No safe conversion available — skip rather than risk
                // corrupting the row; the approximate `credit(foods:)` path
                // stays available as a fallback for callers.
                logger.error("Pantry exact-credit unit mismatch, skipping row \(item.canonicalName, privacy: .public)")
                continue
            }
            item.updatedAt = Date()
            credited += 1
        }
        do {
            try modelContext.save()
            logger.info("Pantry exact-credit: \(credited)/\(details.count) row(s)")
        } catch {
            logger.error("Pantry exact-credit save failed: \(error.localizedDescription, privacy: .public)")
        }
        return credited
    }

    /// Re-credit the pantry by an arbitrary list of foods — the APPROXIMATE
    /// inverse of `decrement(foods:)`, kept as a fallback for meals that
    /// don't carry a recorded `decrementDetail` (e.g. data from before this
    /// feature existed). Prefer `creditExact` whenever detail is available.
    ///
    /// NOTE: this is an APPROXIMATE inverse, not an exact one. The decrement
    /// floored at zero (`max(0, qty - delta)`), so if the meal had depleted an
    /// item (needed 153 g, only 100 g on hand → 0), crediting the *requested*
    /// grams back invents stock that never existed. We accept that drift: the
    /// alternative (logging pre-decrement snapshots per meal) is far heavier,
    /// and over-crediting a depleted staple is a smaller harm than stranding a
    /// meal the user can't undo. Caller guards on `didDecrementPantry` so a
    /// credit happens at most once per undo.
    @discardableResult
    static func credit(
        foods: [PlannedFood],
        label: String,
        modelContext: ModelContext
    ) -> [PantryDecrementResult] {
        let pairs = foods.map { ($0.name, $0.quantityGrams) }
        return apply(pairs: pairs, direction: .credit, label: label, modelContext: modelContext)
    }

    private enum Direction {
        case decrement
        case credit
    }

    /// Shared per-item decrement loop over (canonicalName, grams) pairs.
    private static func decrement(
        pairs: [(String, Double)],
        label: String,
        modelContext: ModelContext
    ) -> [PantryDecrementResult] {
        apply(pairs: pairs, direction: .decrement, label: label, modelContext: modelContext)
    }

    /// Shared per-item pantry mutation over (canonicalName, grams) pairs.
    /// `direction` selects subtract (floor at 0, FIFO across rows) vs the
    /// approximate add-back (single-row, legacy `credit(foods:)` path).
    private static func apply(
        pairs: [(String, Double)],
        direction: Direction,
        label: String,
        modelContext: ModelContext
    ) -> [PantryDecrementResult] {
        guard !pairs.isEmpty else {
            return []
        }

        // Fetch all non-archived pantry rows once and GROUP by canonical
        // name (not index — a canonical name can have several rows: brand
        // duplicates, or a restock bought before the old batch ran out).
        // Pantry size is bounded (~50–150 items); a single fetch is
        // cheaper than per-ingredient predicates.
        let pantryDescriptor = FetchDescriptor<PantryItem>(
            predicate: #Predicate<PantryItem> { item in
                item.isArchived == false
            }
        )
        let pantryRows = (try? modelContext.fetch(pantryDescriptor)) ?? []
        var byName: [String: [PantryItem]] = [:]
        for row in pantryRows {
            byName[row.canonicalName.lowercased(), default: []].append(row)
        }
        // FIFO: earliest useBy first (a row with no useBy sorts last — it's
        // the least urgent to use up first, by definition it has no known
        // expiry pressure).
        for key in byName.keys {
            byName[key]?.sort { lhs, rhs in
                switch (lhs.useBy, rhs.useBy) {
                case let (l?, r?): l < r
                case (nil, nil): false
                case (nil, _): false
                case (_, nil): true
                }
            }
        }

        // Staples (user-tracked, Pantry Smarts) are NEVER decremented —
        // in addition to the pre-existing FoodMacroDatabase.isStaple skip.
        let stapleDescriptor = FetchDescriptor<PantryStaple>()
        let stapleNames = Set(((try? modelContext.fetch(stapleDescriptor)) ?? []).map { $0.canonicalName.lowercased() })

        var results: [PantryDecrementResult] = []
        for (rawName, rawGrams) in pairs {
            let canonical = FoodCanonicalizer.canonicalize(rawName).lowercased()
            guard rawGrams > 0 else {
                continue
            }

            // Staple? Don't decrement (you bought a jar of salt months ago).
            if FoodMacroDatabase.naturalPortions[canonical]?.isStaple == true || stapleNames.contains(canonical) {
                results.append(PantryDecrementResult(
                    canonicalName: canonical,
                    requestedGrams: rawGrams,
                    outcome: .skippedStaple
                ))
                continue
            }

            guard let rows = byName[canonical], !rows.isEmpty else {
                results.append(PantryDecrementResult(
                    canonicalName: canonical,
                    requestedGrams: rawGrams,
                    outcome: .notFound
                ))
                continue
            }

            switch direction {
            case .decrement:
                results.append(decrementFIFO(canonical: canonical, requestedGrams: rawGrams, rows: rows))
            case .credit:
                // Legacy approximate credit — single row (the first match),
                // no FIFO semantics needed since it's a best-effort add-back.
                let row = rows[0]
                let delta = convertGramsToPantryUnit(grams: rawGrams, canonicalName: canonical, unit: row.unit)
                guard let delta else {
                    results.append(PantryDecrementResult(
                        canonicalName: canonical,
                        requestedGrams: rawGrams,
                        outcome: .skippedNoUnitMatch
                    ))
                    continue
                }
                row.quantity = clean(row.quantity + delta)
                row.updatedAt = Date()
                results.append(PantryDecrementResult(
                    canonicalName: canonical,
                    requestedGrams: rawGrams,
                    outcome: .decremented(remaining: row.quantity)
                ))
            }
        }

        let verb = direction == .credit ? "credit" : "decrement"
        do {
            try modelContext.save()
            logger.info("Pantry \(verb, privacy: .public) for \(label, privacy: .public): \(results.count) item(s)")
        } catch {
            // A failed save leaves quantities mutated in memory but not on
            // disk; surfacing the error in the log makes a stale-pantry
            // bug debuggable instead of silently rolling back at relaunch.
            logger
                .error(
                    "Pantry \(verb, privacy: .public) save failed for \(label, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
        }
        return results
    }

    /// Consume `requestedGrams` worth of `canonical` across `rows` (already
    /// sorted earliest-useBy-first), moving to the next row once the current
    /// one is exhausted. Rows whose unit can't be converted are skipped
    /// individually (their stock is left untouched) rather than aborting
    /// the whole ingredient.
    private static func decrementFIFO(
        canonical: String,
        requestedGrams: Double,
        rows: [PantryItem]
    ) -> PantryDecrementResult {
        var remainingGrams = requestedGrams
        var details: [PantryDecrementDetail] = []
        var anyRowMatchedUnit = false
        var totalRemainingStock: Double = 0

        for row in rows {
            guard remainingGrams > 0 else {
                totalRemainingStock += row.quantity
                continue
            }
            guard let neededInRowUnit = convertGramsToPantryUnit(
                grams: remainingGrams, canonicalName: canonical, unit: row.unit
            )
            else {
                // Can't convert for this row's unit — leave it alone, try
                // the next row (a different unit might convert fine).
                totalRemainingStock += row.quantity
                continue
            }
            anyRowMatchedUnit = true
            var consume = min(row.quantity, neededInRowUnit)
            guard consume > 0 else {
                totalRemainingStock += row.quantity
                continue
            }
            // Leave no un-usable dust: a countable row that would end up at
            // or under the depletion threshold is consumed fully.
            if row.unit.isCountable, row.quantity - consume <= row.unit.depletedThreshold {
                consume = row.quantity
            }
            let gramsConsumed = gramsEquivalent(pantryAmount: consume, canonicalName: canonical, unit: row.unit) ?? remainingGrams
            row.quantity = clean(max(0, row.quantity - consume))
            row.updatedAt = Date()
            details.append(PantryDecrementDetail(
                pantryItemID: row.id, canonicalName: canonical, unitRaw: row.unitRaw, amount: consume
            ))
            remainingGrams = max(0, remainingGrams - gramsConsumed)
            totalRemainingStock += row.quantity
        }

        guard anyRowMatchedUnit else {
            return PantryDecrementResult(canonicalName: canonical, requestedGrams: requestedGrams, outcome: .skippedNoUnitMatch)
        }
        let outcome: PantryDecrementResult.Outcome = rows.allSatisfy({ !$0.isInStock })
            ? .depleted
            : .decremented(remaining: totalRemainingStock)
        return PantryDecrementResult(canonicalName: canonical, requestedGrams: requestedGrams, outcome: outcome, details: details)
    }

    // MARK: - Unit conversion

    /// Snap float dust (0.30000000000000004) so quantities stay readable and
    /// decrement → credit round-trips to the exact starting value.
    nonisolated static func clean(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }

    static let gramsPerOunce = 28.349523125
    static let gramsPerPound = 453.59237

    /// Translate a recipe gram quantity into the pantry item's stored unit.
    /// Returns nil when the unit can't be converted (caller surfaces a
    /// `skippedNoUnitMatch` result so the user can see what was missed).
    ///
    /// Conversion strategy:
    /// - Mass / volume units: direct math (g, kg, mL, L). Liquids assumed
    ///   1 g/mL (water-like) — staples like oil drift ~8% but never
    ///   decrement anyway.
    /// - Countable container units (.cans/.bottles/.jars/.packs/.pieces):
    ///   divide grams by the naturalPortion's per-unit weight (see
    ///   `PantryUnit.gramsPerUnit`). NOT rounded — the pantry tracks
    ///   fractions (0.2 pack) so a small bite never empties a whole pack.
    static func convertGramsToPantryUnit(
        grams: Double,
        canonicalName: String,
        unit: PantryUnit
    ) -> Double? {
        switch unit {
        case .grams:
            return grams
        case .kilograms:
            return grams / 1000
        case .milliliters:
            return grams
        case .liters:
            return grams / 1000
        case .pieces,
             .cans,
             .bottles,
             .jars,
             .packs:
            // Fractional: 100 g of a 500 g pack is 0.2 pack, never a whole
            // emptied pack. Containers use the purchase weight, pieces the
            // per-item weight (`PantryUnit.gramsPerUnit`).
            guard let portion = FoodMacroDatabase.naturalPortions[canonicalName],
                  let perUnit = unit.gramsPerUnit(of: portion)
            else {
                return nil
            }
            return grams / perUnit
        case .ounces:
            return grams / gramsPerOunce
        case .pounds:
            return grams / gramsPerPound
        case .servings:
            // One serving ≈ one natural portion (1 egg, 40 g oats…).
            guard let portion = FoodMacroDatabase.naturalPortions[canonicalName], portion.grams > 0 else {
                return nil
            }
            return grams / portion.grams
        }
    }

    /// Inverse of `convertGramsToPantryUnit`: how many grams a given amount
    /// IN THE PANTRY'S OWN UNIT represents. Used by the FIFO loop to debit
    /// the right amount from `remainingGrams` after a row only partially
    /// covers the requirement (e.g. row had 2 cans, needed 3 → row supplies
    /// 2 cans' worth of grams, remainder rolls to the next row).
    static func gramsEquivalent(
        pantryAmount: Double,
        canonicalName: String,
        unit: PantryUnit
    ) -> Double? {
        switch unit {
        case .grams,
             .milliliters:
            return pantryAmount
        case .kilograms,
             .liters:
            return pantryAmount * 1000
        case .ounces:
            return pantryAmount * gramsPerOunce
        case .pounds:
            return pantryAmount * gramsPerPound
        case .pieces,
             .cans,
             .bottles,
             .jars,
             .packs:
            guard let portion = FoodMacroDatabase.naturalPortions[canonicalName],
                  let perUnit = unit.gramsPerUnit(of: portion)
            else {
                return nil
            }
            return pantryAmount * perUnit
        case .servings:
            guard let portion = FoodMacroDatabase.naturalPortions[canonicalName], portion.grams > 0 else {
                return nil
            }
            return pantryAmount * portion.grams
        }
    }
}
