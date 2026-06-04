//
// MealFeedback.swift
// Tempo
//
// Created by Tempo on 13/05/2026.
//

import Foundation
import SwiftData

// MARK: - MealFeel

/// One-word post-meal sensation captured right after marking eaten.
/// Subjective but high-signal when aggregated: over weeks the AI learns
/// which dishes pair with which states ("Mediterranean lunches → energising
/// 80% of the time, big pasta lunches → sluggish 75%") and biases plan
/// generation accordingly.
///
/// Five chips, no more. Adding a sixth is a feature creep red flag — pick
/// values that ladder from light→heavy with two qualitative outliers
/// (`clean`, `energising`).
enum MealFeel: String, Codable, CaseIterable, Sendable {
    case light
    case clean
    case energising
    case heavy
    case sluggish

    /// User-facing label. Display capitalised in chips.
    var displayName: String {
        switch self {
        case .light: "Light"
        case .clean: "Clean"
        case .energising: "Energising"
        case .heavy: "Heavy"
        case .sluggish: "Sluggish"
        }
    }

    /// SF Symbol that pairs with the chip — visual scaffolding for users
    /// who scan icons faster than words.
    var symbolName: String {
        switch self {
        case .light: "leaf.fill"
        case .clean: "checkmark.seal.fill"
        case .energising: "bolt.fill"
        case .heavy: "scalemass.fill"
        case .sluggish: "cloud.fill"
        }
    }

    /// True when this feel signals a problem the planner should bias
    /// away from. `heavy` is borderline — kept positive on rest days.
    var isNegativeSignal: Bool {
        self == .sluggish
    }
}

// MARK: - MealSatiety

/// How full the meal left the user — the satiety signal. The PRIMARY direction
/// the user cares about is DOWN: flagging a meal that was too much / they
/// couldn't finish, so the planner scales that slot's portion down over time
/// (fits a lean-recomposition goal — don't force-feed). `stillHungry` is the
/// secondary, scale-UP direction.
enum MealSatiety: String, Codable, CaseIterable, Sendable {
    case tooMuch = "too_much"
    case didntFinish = "didnt_finish"
    case justRight = "just_right"
    case stillHungry = "still_hungry"

    var displayName: String {
        switch self {
        case .tooMuch: "Too much"
        case .didntFinish: "Didn't finish"
        case .justRight: "Just right"
        case .stillHungry: "Still hungry"
        }
    }

    var symbolName: String {
        switch self {
        case .tooMuch: "arrow.down.circle.fill"
        case .didntFinish: "fork.knife.circle"
        case .justRight: "checkmark.circle.fill"
        case .stillHungry: "arrow.up.circle.fill"
        }
    }

    /// True when the signal asks the planner to CHANGE the slot's portion
    /// (down for too-much/didn't-finish, up for still-hungry). `justRight` is
    /// the confirmation case — no change.
    var requestsPortionChange: Bool {
        self != .justRight
    }
}

// MARK: - IngredientSentiment

/// Per-ingredient sentiment, captured so the AI can distinguish "I dislike
/// rice everywhere" from "rice in *this* dish was wrong." `wrongForm` is for
/// "I'd prefer this raw / grilled / pickled" — preserves nuance the
/// next plan generation can act on.
enum IngredientSentiment: String, Codable, CaseIterable, Sendable {
    case liked
    case disliked
    case neutral
    case wrongForm = "wrong_form"
    case portionTooBig = "portion_too_big"
    case portionTooSmall = "portion_too_small"
}

// MARK: - IngredientNote

/// Structured note about a single ingredient inside a meal.
struct IngredientNote: Codable, Sendable, Equatable {
    /// Lowercased canonical name so AI lookup and grouping work without
    /// fuzzy matching at consumption time.
    var ingredientName: String
    var sentiment: IngredientSentiment
    var note: String?
}

// MARK: - MealFeedback

/// User feedback on a single eaten `PlannedMeal`. Captured inline on
/// mark-eaten, on the past-meal review badge, or in the end-of-week review
/// screen. Read by `MealPlanGeneratorService` when generating the next week
/// so plans reflect what the user actually liked / disliked / wanted
/// adjusted.
///
/// Design notes:
/// - `recipeID` is denormalized so the row survives `PlannedMeal` deletion
///   (cascade rule from `Recipe` would otherwise orphan everything).
/// - `ingredientNotesJSON` stores `[IngredientNote]` as Data because
///   SwiftData natively supports only primitive arrays. Access via the
///   `ingredientNotes` transient.
/// - `rating` is optional — many users only leave a note, not a star.
@Model
final class MealFeedback {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    var createdAt: Date

    // MARK: - Scope

    /// The PlannedMeal this feedback is about. Nullified if the meal is
    /// deleted; `recipeID` below survives for AI lookup.
    @Relationship(deleteRule: .nullify)
    var plannedMeal: PlannedMeal?

    /// Denormalized recipe id at the time the feedback was created.
    /// Allows plan generator to group feedback by recipe even after
    /// `PlannedMeal` rows for old weeks are pruned.
    var recipeID: UUID?

    /// Denormalized recipe name. Cheaper than a join when surfacing in the
    /// end-of-week review or feeding text into a prompt.
    var recipeName: String?

    /// The meal slot this feedback was attached to (1=Breakfast..4=Snack).
    /// Lets the AI weight feedback per-slot ("user dislikes heavy lunches").
    var mealNumber: Int

    // MARK: - Content

    /// 1–5 star rating. Nil = no rating given.
    var rating: Int?

    /// Free-text overall comment ("loved this", "didn't like the mix").
    var overallNote: String?

    /// Portion feedback as freeform text ("too big", "perfect for me", "100g
    /// not 300g"). Kept distinct from `overallNote` so the AI can apply
    /// portion adjustments without conflating with taste preferences.
    var portionNote: String?

    /// Specific change the user would like applied next time
    /// ("add lemon", "swap rice for quinoa", "less salt"). The AI is told
    /// to honour these on regeneration.
    var suggestedChange: String?

    /// One-word post-meal feel captured by `MarkEatenSheet`. Stored as
    /// `MealFeel.rawValue` so SwiftData can persist it natively.
    /// `mealFeelEnum` is the typed accessor.
    var mealFeelRaw: String?

    /// Free-text description of what the user ate instead of the planned
    /// meal ("chicken, rice, beans, olive oil"). Set by the "Ate something
    /// else" lane in `MarkEatenSheet`. When non-nil, the planned meal's
    /// macros have been zeroed on the `PlannedMeal` row; the kcal estimate
    /// below is the only macro signal we have.
    var substituteNote: String?

    /// Rough calorie estimate the user typed for the substitute meal.
    /// Optional — many users skip this. AI prompt is told to treat
    /// "unknown" as "user ate something but didn't quantify it."
    var substituteCalories: Double?

    @Transient
    var mealFeel: MealFeel? {
        get { mealFeelRaw.flatMap { MealFeel(rawValue: $0) } }
        set { mealFeelRaw = newValue?.rawValue }
    }

    /// Satiety signal — how full the meal left the user. Additive, defaults
    /// nil. Drives portion scaling in the next plan (mainly DOWN for
    /// too-much / didn't-finish).
    var satietyRaw: String?

    @Transient
    var satiety: MealSatiety? {
        get { satietyRaw.flatMap { MealSatiety(rawValue: $0) } }
        set { satietyRaw = newValue?.rawValue }
    }

    // MARK: - Per-Ingredient Notes

    var ingredientNotesJSON: Data?

    @Transient
    var ingredientNotes: [IngredientNote] {
        get {
            guard let data = ingredientNotesJSON else {
                return []
            }
            return (try? JSONDecoder().decode([IngredientNote].self, from: data)) ?? []
        }
        set {
            ingredientNotesJSON = newValue.isEmpty
                ? nil
                : try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        plannedMeal: PlannedMeal? = nil,
        recipeID: UUID? = nil,
        recipeName: String? = nil,
        mealNumber: Int = 0,
        rating: Int? = nil,
        overallNote: String? = nil,
        portionNote: String? = nil,
        suggestedChange: String? = nil,
        mealFeel: MealFeel? = nil,
        satiety: MealSatiety? = nil,
        substituteNote: String? = nil,
        substituteCalories: Double? = nil,
        ingredientNotes: [IngredientNote] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.plannedMeal = plannedMeal
        self.recipeID = recipeID ?? plannedMeal?.recipe?.id
        self.recipeName = recipeName ?? plannedMeal?.recipe?.name
        self.mealNumber = plannedMeal?.mealNumber ?? mealNumber
        // Rating is 1–5 by UX contract; clamp non-nil values, drop out-of-range zero.
        self.rating = rating.map { max(1, min(5, $0)) }
        self.overallNote = overallNote
        self.portionNote = portionNote
        self.suggestedChange = suggestedChange
        self.mealFeelRaw = mealFeel?.rawValue
        self.satietyRaw = satiety?.rawValue
        self.substituteNote = substituteNote
        self.substituteCalories = substituteCalories
        ingredientNotesJSON = ingredientNotes.isEmpty
            ? nil
            : try? JSONEncoder().encode(ingredientNotes)
    }

    // MARK: - Helpers

    /// True when the feedback has any actionable signal. Used to decide if
    /// the row is worth feeding into the next plan-generation prompt.
    @Transient
    var hasSignal: Bool {
        if let rating, rating > 0 {
            return true
        }
        if let overallNote, !overallNote.isEmpty {
            return true
        }
        if let portionNote, !portionNote.isEmpty {
            return true
        }
        if let suggestedChange, !suggestedChange.isEmpty {
            return true
        }
        if mealFeel != nil {
            return true
        }
        if satiety != nil {
            return true
        }
        if let substituteNote, !substituteNote.isEmpty {
            return true
        }
        return !ingredientNotes.isEmpty
    }
}
