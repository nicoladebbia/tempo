//
// PlannedMeal.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import SwiftData

// MARK: - PlannedFood

struct PlannedFood: Codable, Equatable {
    let name: String
    let quantityGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    /// Where the numbers come from: "usda" (verified), "ai", or "restaurant"
    /// (a menu item — approximate). nil on older plans and manual logs.
    var source: String?
    /// Restaurant for a meal-out item ("Panera Bread").
    var restaurant: String?

    /// A menu item whose macros are an estimate, not a weighed home portion.
    var isApproximate: Bool {
        source == "restaurant"
    }
}

// MARK: - MealMacros

/// Plain macro totals (kcal + grams). Used for a meal's plan baseline and for
/// summing canonical eaten meals without dragging SwiftData types around.
struct MealMacros: Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = MealMacros(calories: 0, protein: 0, carbs: 0, fat: 0)

    static func + (lhs: MealMacros, rhs: MealMacros) -> MealMacros {
        MealMacros(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }
}

// MARK: - ReplacedPlan

/// The planned dish a log replaced, kept so Undo / Delete can bring it back.
struct ReplacedPlan: Codable, Equatable {
    let foods: [PlannedFood]
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    var totals: MealMacros {
        MealMacros(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    init(foods: [PlannedFood], totals: MealMacros) {
        self.foods = foods
        calories = totals.calories
        protein = totals.protein
        carbs = totals.carbs
        fat = totals.fat
    }
}

// MARK: - PlannedMeal

@Model
final class PlannedMeal: Identifiable {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    // MARK: - Scheduling

    /// Calendar date normalized to midnight.
    var dayDate: Date

    /// Meal slot number (1-6).
    var mealNumber: Int

    /// Display name (e.g. "Breakfast", "Lunch").
    var mealName: String

    /// Scheduled time as HH:mm string (e.g. "07:30").
    var scheduledTime: String

    // MARK: - Foods

    var foodsJSON: Data?

    // MARK: - Macro Totals

    var totalCalories: Double

    var totalProtein: Double

    var totalCarbs: Double

    var totalFat: Double

    // MARK: - Status

    var statusRaw: String

    var linkedMealLogID: UUID?

    /// True once this meal's pantry stock has been decremented (recipe
    /// ingredients OR substitute foods). Guards against double-subtract: a
    /// meal decrements the pantry AT MOST ONCE, even if the user re-marks it
    /// eaten or corrects a substitute. Additive migration, default false.
    var didDecrementPantry: Bool = false

    /// Per-row amounts actually subtracted from the pantry when this meal
    /// was decremented (`PantryDecrementService.decrement`), JSON-encoded
    /// `[PantryDecrementDetail]`. Lets `undoMealEaten` credit back EXACTLY
    /// what was taken, from exactly the pantry rows it came from, instead of
    /// re-deriving an approximate inverse from the recipe. Nil for meals
    /// decremented before this field existed, or when nothing matched any
    /// pantry stock — those fall back to the approximate `credit(foods:)`.
    var decrementDetailJSON: Data?

    /// Convenience accessor — decodes/encodes `decrementDetailJSON`.
    @Transient
    var decrementDetail: [PantryDecrementDetail] {
        get {
            guard let decrementDetailJSON else {
                return []
            }
            return (try? JSONDecoder().decode([PantryDecrementDetail].self, from: decrementDetailJSON)) ?? []
        }
        set {
            decrementDetailJSON = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    /// Wall-clock time the user actually ate this meal. Set by
    /// `NutritionTabViewModel.markMealEaten`. Drives the deterministic
    /// shift of subsequent meals (`MealShiftPlanner`) and feeds into
    /// future plan generation as the user's real rhythm signal.
    /// Nil for `.planned` / `.skipped` meals.
    var actualEatenAt: Date?

    /// The macros the PLAN allocated to this slot, frozen before anything
    /// rewrites `total*` (a logged substitute, the same-day rebalancer, a
    /// skip redistribution). The daily target sums these, so the target stays
    /// put when the user eats something bigger or the rebalancer bumps the
    /// remaining meals — without it the target was the live sum of the meals
    /// and every rebalance re-applied itself. `0` = an ad-hoc log the plan
    /// never asked for. nil = never captured → falls back to `total*`.
    /// Optional so the SwiftData field add is a lightweight migration.
    var planBaselineCalories: Double?
    var planBaselineProtein: Double?
    var planBaselineCarbs: Double?
    var planBaselineFat: Double?

    /// Explicit "the user logged this on top of the plan" marker, set by
    /// `markAsUnplannedLog`. A zero baseline alone must not mean "ad-hoc": a
    /// rebuilt plan meal can legitimately get a tiny/zero allotment. nil on
    /// rows written before the flag existed (legacy zero-baseline fallback in
    /// `isUnplannedLog`). Optional so the field add is a lightweight migration.
    var isUnplannedLogFlag: Bool?

    /// What the plan had in this slot before a log REPLACED it ("I ate
    /// something else", or a Quick Log landing in a planned slot): the
    /// planned foods + totals as JSON (`ReplacedPlan`). Undo / delete of the
    /// log restores them so the planned dish comes back. nil = nothing was
    /// replaced. Optional so the SwiftData field add is a lightweight migration.
    var replacedPlanJSON: Data?

    /// How long the user expects to spend eating. Drives the "eat-finish" time
    /// surfaced in `MealDetailView`. Default 30 minutes.
    var eatDurationMinutes: Int

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var mealPlan: WeeklyMealPlan?

    /// AI-generated recipe attached to this planned meal. Created at plan-generation
    /// time by `MealPlanGeneratorService` via Claude Haiku. Cascade-deleted so an
    /// orphan PlannedMeal never points at a stale Recipe.
    @Relationship(deleteRule: .cascade)
    var recipe: Recipe?

    /// The planned recipe parked here while a log has replaced the slot's
    /// dish (so `recipe` renders the foods actually eaten). Moved back to
    /// `recipe` when the log is undone / deleted.
    @Relationship(deleteRule: .cascade)
    var replacedRecipe: Recipe?

    // MARK: - Computed Properties

    @Transient
    var foods: [PlannedFood] {
        get {
            guard let data = foodsJSON else {
                return []
            }
            return (try? JSONDecoder().decode([PlannedFood].self, from: data)) ?? []
        }
        set {
            foodsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    @Transient
    var status: MealStatus {
        get { MealStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    @Transient
    var formattedTime: String {
        scheduledTime
    }

    @Transient
    var foodCount: Int {
        foods.count
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        dayDate: Date,
        mealNumber: Int = 1,
        mealName: String = "Meal",
        scheduledTime: String = "12:00",
        foods: [PlannedFood] = [],
        totalCalories: Double = 0,
        totalProtein: Double = 0,
        totalCarbs: Double = 0,
        totalFat: Double = 0,
        status: MealStatus = .planned,
        linkedMealLogID: UUID? = nil,
        actualEatenAt: Date? = nil,
        eatDurationMinutes: Int = 30,
        mealPlan: WeeklyMealPlan? = nil,
        recipe: Recipe? = nil
    ) {
        self.id = id
        self.dayDate = Calendar.current.startOfDay(for: dayDate)
        self.mealNumber = mealNumber
        self.mealName = mealName
        self.scheduledTime = scheduledTime
        foodsJSON = foods.isEmpty ? nil : try? JSONEncoder().encode(foods)
        self.totalCalories = totalCalories
        self.totalProtein = totalProtein
        self.totalCarbs = totalCarbs
        self.totalFat = totalFat
        statusRaw = status.rawValue
        self.linkedMealLogID = linkedMealLogID
        self.actualEatenAt = actualEatenAt
        self.eatDurationMinutes = max(0, eatDurationMinutes)
        self.mealPlan = mealPlan
        self.recipe = recipe
    }

    /// What this meal contributes to the day's TARGET (not to "eaten").
    /// Captured baseline when present; a meal never tied to a plan is an
    /// ad-hoc log and contributes nothing; otherwise the live totals (an
    /// untouched plan meal).
    @Transient
    var planBaseline: MealMacros {
        if let planBaselineCalories {
            return MealMacros(
                calories: planBaselineCalories,
                protein: planBaselineProtein ?? 0,
                carbs: planBaselineCarbs ?? 0,
                fat: planBaselineFat ?? 0
            )
        }
        if mealPlan == nil {
            return .zero
        }
        return totals
    }

    @Transient
    var totals: MealMacros {
        MealMacros(calories: totalCalories, protein: totalProtein, carbs: totalCarbs, fat: totalFat)
    }

    /// Freezes the current totals as the plan baseline. Call before ANY code
    /// rewrites `total*`. No-op once captured, and for unbound (ad-hoc) meals.
    /// Returns true when it wrote something (so callers know to save).
    @discardableResult
    func capturePlanBaselineIfNeeded() -> Bool {
        guard planBaselineCalories == nil, mealPlan != nil else {
            return false
        }
        planBaselineCalories = totalCalories
        planBaselineProtein = totalProtein
        planBaselineCarbs = totalCarbs
        planBaselineFat = totalFat
        return true
    }

    /// Marks a user-logged meal as outside the plan: it counts as eaten but
    /// adds nothing to the day's target, even when it's attached to the plan.
    func markAsUnplannedLog() {
        isUnplannedLogFlag = true
        planBaselineCalories = 0
        planBaselineProtein = 0
        planBaselineCarbs = 0
        planBaselineFat = 0
    }

    /// True for a meal the user logged on top of the plan (Quick Log, scan,
    /// photo, voice, preset): flagged by `markAsUnplannedLog`. Undoing or
    /// deleting one REMOVES it — it was never a plan slot, so reverting it to
    /// `.planned` would invent an upcoming meal. Rows from before the flag
    /// existed (flag nil) fall back to the old signal: a frozen all-zero
    /// baseline. Logs from before this existed that never got a baseline carry
    /// no reliable signal and stay as they are. An explicit `false` (set on rebuilt plan meals) never reads
    /// as a log.
    @Transient
    var isUnplannedLog: Bool {
        if let isUnplannedLogFlag {
            return isUnplannedLogFlag
        }
        guard let calories = planBaselineCalories else {
            return false
        }
        return calories == 0 && (planBaselineProtein ?? 0) == 0
            && (planBaselineCarbs ?? 0) == 0 && (planBaselineFat ?? 0) == 0
    }

    /// The plan's original dish for this slot when a log replaced it.
    @Transient
    var replacedPlan: ReplacedPlan? {
        get {
            guard let replacedPlanJSON else {
                return nil
            }
            return try? JSONDecoder().decode(ReplacedPlan.self, from: replacedPlanJSON)
        }
        set {
            replacedPlanJSON = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    /// Parks the planned dish (foods, totals, recipe) before a log overwrites
    /// it. First call wins, so re-logging the same slot never loses the
    /// ORIGINAL plan. No-op for an ad-hoc log (nothing was planned).
    func stashPlannedDishIfNeeded() {
        guard replacedPlanJSON == nil, !isUnplannedLog else {
            return
        }
        replacedPlan = ReplacedPlan(foods: foods, totals: totals)
        if let recipe {
            replacedRecipe = recipe
            self.recipe = nil
        }
    }

    /// Puts the planned dish back (foods, totals, recipe). Returns false when
    /// nothing was stashed.
    @discardableResult
    func restoreReplacedPlan() -> Bool {
        guard let stashed = replacedPlan else {
            return false
        }
        foods = stashed.foods
        totalCalories = stashed.totals.calories
        totalProtein = stashed.totals.protein
        totalCarbs = stashed.totals.carbs
        totalFat = stashed.totals.fat
        if let replacedRecipe {
            recipe = replacedRecipe
            self.replacedRecipe = nil
        }
        replacedPlanJSON = nil
        return true
    }

    /// Recalculate totals from current foods.
    func recalculateTotals() {
        let currentFoods = foods
        totalCalories = currentFoods.reduce(0) { $0 + $1.calories }
        totalProtein = currentFoods.reduce(0) { $0 + $1.proteinG }
        totalCarbs = currentFoods.reduce(0) { $0 + $1.carbsG }
        totalFat = currentFoods.reduce(0) { $0 + $1.fatG }
    }
}
