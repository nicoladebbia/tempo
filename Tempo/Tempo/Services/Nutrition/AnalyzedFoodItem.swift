//
// AnalyzedFoodItem.swift
// Tempo
//
// One food row of a meal-photo analysis while the user is still correcting it
// (rename, swap to an alternative, change the portion, answer a question).
// All the correction rules live here so they are unit-testable; the view only
// calls them. Macros are re-checked against the built-in food table whenever
// the identification changes.
//

import Foundation

struct AnalyzedFoodItem: Identifiable {
    let id: UUID
    var name: String
    var estimatedPortion: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    /// Model confidence 0...1; a user answer raises it to `userConfirmedScore`.
    var score: Double
    var servingMultiplier: Double
    /// Alternative identifications from the vision model, ranked by
    /// descending confidence. Empty when the food is unambiguous.
    var alternatives: [PhotoAnalysisResult.FoodCandidate] = []
    /// Macros were checked against a food database (USDA or the built-in table).
    var isVerified = false
    /// The model's own clarifying question, when it asked one.
    var question: String?

    static let userConfirmedScore = 0.95
    /// Below this the row asks the user instead of guessing.
    static let questionThreshold = 0.6

    var confidence: ConfidenceLevel {
        ConfidenceLevel(score: score)
    }

    var confidencePercent: Int {
        Int((score * 100).rounded())
    }

    var needsQuestion: Bool {
        score < Self.questionThreshold
    }

    /// "Is this grilled chicken or pork?" — the model's question, else one built from its top alternative.
    var clarifyingQuestion: String {
        if let question, !question.isEmpty {
            return question
        }
        if let first = alternatives.first {
            return "Is this \(name.lowercased()) or \(first.name.lowercased())?"
        }
        return "Is this \(name.lowercased())?"
    }

    /// Grams of the estimated portion, 0 when the portion isn't a weight ("1 cup").
    var portionGrams: Double {
        EatenMealRecorder.gramsFromServingSize(estimatedPortion)
    }

    // MARK: - Corrections

    /// The user says the guess is right.
    mutating func confirm() {
        score = max(score, Self.userConfirmedScore)
        question = nil
    }

    /// Swap to a ranked alternative: name, portion and macros move together,
    /// the old best guess becomes an alternative so the user can swap back,
    /// and the new identification is re-checked against the food table.
    func applying(_ candidate: PhotoAnalysisResult.FoodCandidate) -> AnalyzedFoodItem {
        let previous = PhotoAnalysisResult.FoodCandidate(
            id: UUID().uuidString,
            name: name,
            estimatedPortion: estimatedPortion,
            calories: Double(calories),
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            confidence: score
        )
        var rest = alternatives.filter { $0.id != candidate.id }
        rest.insert(previous, at: 0)
        let swapped = AnalyzedFoodItem(
            id: id,
            name: candidate.name,
            estimatedPortion: candidate.estimatedPortion,
            calories: Int(candidate.calories.rounded()),
            protein: candidate.proteinGrams,
            carbs: candidate.carbsGrams,
            fat: candidate.fatGrams,
            score: max(candidate.confidence, Self.userConfirmedScore),
            servingMultiplier: servingMultiplier,
            alternatives: rest
        )
        return swapped.reverified()
    }

    /// The user typed what it really is. Keeps the portion; macros come from the
    /// food table when it knows the food, else stay as the photo estimate.
    func renamed(to newName: String) -> AnalyzedFoodItem {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else {
            return self
        }
        var copy = self
        copy.name = trimmed
        copy.question = nil
        copy.isVerified = false
        var checked = copy.reverified()
        // Only claim certainty when the food table backed the new name; otherwise the old numbers stay
        // a guess, kept below the question threshold so the row still asks the user to check them.
        checked.score = checked.isVerified ? Self.userConfirmedScore : min(score, Self.questionThreshold - 0.05)
        return checked
    }

    /// Re-check against the built-in food table. Needs a weight to scale
    /// from: a portion in grams, else 100 g is assumed and shown.
    func reverified() -> AnalyzedFoodItem {
        guard let macros = FoodMacroDatabase.lookup(name) else {
            return self
        }
        var copy = self
        let grams = portionGrams
        guard grams > 0 else {
            return self // "1 cup" / "2 slices": no weight to scale from
        }
        let scaled = macros.scaled(to: grams)
        copy.calories = Int(scaled.calories.rounded())
        copy.protein = scaled.protein.rounded()
        copy.carbs = scaled.carbs.rounded()
        copy.fat = scaled.fat.rounded()
        copy.isVerified = true
        return copy
    }

    /// An item the model missed, added by hand. Nil when there is nothing to
    /// compute from: the food isn't in the table and no calories were typed.
    static func manual(name: String, grams: Double, kcal: Double?) -> AnalyzedFoodItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, grams > 0 else {
            return nil
        }
        let base = AnalyzedFoodItem(
            id: UUID(),
            name: trimmed,
            estimatedPortion: "\(Int(grams.rounded()))g",
            calories: Int((kcal ?? 0).rounded()),
            protein: 0,
            carbs: 0,
            fat: 0,
            score: userConfirmedScore,
            servingMultiplier: 1
        )
        let checked = base.reverified()
        if checked.isVerified {
            return checked
        }
        guard let kcal, kcal > 0 else {
            return nil
        }
        return base
    }

    // MARK: - Totals / output

    /// Calories after the serving multiplier.
    var scaledCalories: Int {
        Int((Double(calories) * servingMultiplier).rounded())
    }

    func asFoodItem() -> FoodItem {
        FoodItem(
            id: UUID(),
            name: name,
            brand: nil,
            servingSize: estimatedPortion,
            servingQuantity: servingMultiplier,
            calories: scaledCalories,
            protein: protein * servingMultiplier,
            carbs: carbs * servingMultiplier,
            fat: fat * servingMultiplier
        )
    }
}

extension ConfidenceLevel {
    init(score: Double) {
        if score >= 0.8 {
            self = .high
        } else if score >= 0.5 {
            self = .medium
        } else {
            self = .low
        }
    }
}
