//
// FoodFit.swift
// Tempo
//
// The "For you" half of the product screen: the Tempo score says whether a
// product is good in general; these checks say whether it's good for THIS
// user today — protein density, whether the portion fits what's left of
// today's canonical target (DailyNutritionTargets, same number as the
// Dashboard and Nutrition Today), and the diet profile's hard rules
// (allergies, vegan, gluten, clear-skin dairy, added sugar).
//

import Foundation
import SwiftData

// MARK: - FoodFitCheck

struct FoodFitCheck: Equatable, Hashable, Sendable, Identifiable {
    enum Kind: Int, Sendable {
        /// Conflicts with a hard rule (allergy, vegan…).
        case conflict = 0
        case warning = 1
        case good = 2
    }

    let kind: Kind
    let text: String

    var id: String {
        "\(kind.rawValue)-\(text)"
    }
}

// MARK: - FoodFitContext

/// What the checks need to know about the user — plain values so the checks
/// stay pure and testable.
struct FoodFitContext: Equatable, Sendable {
    var remainingCalories: Int?
    var remainingProtein: Int?
    var clearSkinFocus = false
    var lactoseFree = false
    var glutenFree = false
    var vegan = false
    var vegetarian = false
    var nutFree = false
    var shellfishAllergy = false
    var avoidAddedSugars = false
    /// Free-text allergies from the diet profile ("sesame", "kiwi").
    var allergies: [String] = []

    static let none = FoodFitContext()

    /// Reads the active diet profile, clear-skin setting and what's left of
    /// today's canonical target.
    @MainActor
    static func load(
        in context: ModelContext,
        targets: DailyNutritionTargets,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> FoodFitContext {
        let eaten = CanonicalMeals.totals(of: CanonicalMeals.eatenMeals(on: now, in: context))
        let profile = (try? context.fetch(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true })))?.first
        return FoodFitContext(
            remainingCalories: targets.calories - Int(eaten.calories.rounded()),
            remainingProtein: targets.protein - Int(eaten.protein.rounded()),
            clearSkinFocus: ClearSkinFocusSetting.resolve(modelContext: context, defaults: defaults),
            lactoseFree: profile?.isLactoseFree ?? false,
            glutenFree: profile?.isGlutenFree ?? false,
            vegan: profile?.isVegan ?? false,
            vegetarian: profile?.isVegetarian ?? false,
            nutFree: profile?.isNutFree ?? false,
            shellfishAllergy: profile?.isShellFishAllergy ?? false,
            avoidAddedSugars: profile?.avoidAddedSugars ?? false,
            allergies: profile?.allergies ?? []
        )
    }

    /// Today's context against the canonical daily target (the number the
    /// Nutrition ring shows), using today's stored recovery when there is one.
    @MainActor
    static func loadToday(in context: ModelContext, whoopAvgTDEE: Double?, now: Date = Date()) -> FoodFitContext {
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? now
        let recovery = (try? context.fetch(FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )))?.first?.recoveryScore
        let targets = DailyNutritionTargets.today(in: context, whoopAvgTDEE: whoopAvgTDEE, recoveryScore: recovery)
        return load(in: context, targets: targets, now: now)
    }
}

// MARK: - FoodFit

enum FoodFit {
    /// Checks for `grams` of `product`, conflicts first.
    static func checks(for product: FoodProduct, grams: Double, context: FoodFitContext) -> [FoodFitCheck] {
        var checks: [FoodFitCheck] = []
        let allergens = Set(product.allergens)
        let analysis = Set(product.ingredientsAnalysis)
        let ingredients = (product.ingredientsText ?? "").lowercased()

        // Hard rules.
        if context.glutenFree, allergens.contains("gluten") {
            checks.append(.init(kind: .conflict, text: "Contains gluten"))
        }
        if context.nutFree, !allergens.isDisjoint(with: ["nuts", "peanuts"]) {
            checks.append(.init(kind: .conflict, text: "Contains nuts"))
        }
        if context.shellfishAllergy, !allergens.isDisjoint(with: ["crustaceans", "molluscs"]) {
            checks.append(.init(kind: .conflict, text: "Contains shellfish"))
        }
        if context.vegan {
            if analysis.contains("non-vegan") {
                checks.append(.init(kind: .conflict, text: "Not vegan"))
            } else if analysis.contains("maybe-vegan") || analysis.contains("vegan-status-unknown") {
                checks.append(.init(kind: .warning, text: "May not be vegan — check the ingredients"))
            }
        } else if context.vegetarian, analysis.contains("non-vegetarian") {
            checks.append(.init(kind: .conflict, text: "Not vegetarian"))
        }
        for allergy in context.allergies {
            let term = allergy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard term.count >= 3 else {
                continue
            }
            let tagged = allergens.contains { $0.contains(term) || term.contains($0) }
            if tagged || ingredients.contains(term) {
                checks.append(.init(kind: .conflict, text: "Contains \(allergy) (your allergy)"))
            }
        }

        // Soft rules.
        let hasMilk = allergens.contains("milk")
        let lactoseFreeLabel = product.labels.contains { $0.contains("lactose-free") || $0.contains("no-lactose") }
        if context.lactoseFree, hasMilk, !lactoseFreeLabel {
            checks.append(.init(kind: .warning, text: "Contains lactose"))
        } else if context.clearSkinFocus, hasMilk {
            checks.append(.init(kind: .warning, text: "Dairy — you're in clear-skin mode"))
        }
        let noAddedSugarLabel = product.labels.contains { $0.contains("no-added-sugar") }
        if context.avoidAddedSugars, let sugars = product.per100g.sugars, sugars > 5, !noAddedSugarLabel {
            checks.append(.init(kind: .warning, text: "\(format(sugars)) g sugar per 100 g — you're avoiding added sugar"))
        }
        if product.novaGroup == 4 {
            checks.append(.init(kind: .warning, text: "Ultra-processed (NOVA 4)"))
        }

        // Today's numbers.
        let portion = product.nutrients(forGrams: grams)
        if let kcal = portion.kcal, let remaining = context.remainingCalories {
            let portionKcal = Int(kcal.rounded())
            if remaining <= 0 {
                checks.append(.init(kind: .warning, text: "You've hit today's calories — this adds \(portionKcal) kcal"))
            } else if portionKcal <= remaining {
                checks.append(.init(kind: .good, text: "Fits today: \(portionKcal) kcal of \(remaining) left"))
            } else {
                checks.append(.init(kind: .warning, text: "\(portionKcal) kcal — only \(remaining) left today"))
            }
        }
        if let density = proteinPer100Kcal(product) {
            if density >= 8 {
                checks.append(.init(kind: .good, text: "High protein: \(format(density)) g per 100 kcal"))
            } else if density < 2, (product.per100g.kcal ?? 0) >= 150 {
                checks.append(.init(kind: .warning, text: "Low protein: \(format(density)) g per 100 kcal"))
            }
        }
        if let protein = portion.protein, let remainingProtein = context.remainingProtein, remainingProtein > 0, protein >= 10 {
            checks.append(.init(kind: .good, text: "\(Int(protein.rounded())) g protein toward the \(remainingProtein) g you still need"))
        }
        return checks.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    static func proteinPer100Kcal(_ product: FoodProduct) -> Double? {
        guard let kcal = product.per100g.kcal, kcal > 5, let protein = product.per100g.protein else {
            return nil
        }
        return protein / kcal * 100
    }

    private static func format(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }
}
