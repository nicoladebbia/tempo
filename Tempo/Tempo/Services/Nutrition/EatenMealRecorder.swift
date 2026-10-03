//
// EatenMealRecorder.swift
// Tempo
//
// The one write path for "the user ate these foods". Both the Log tab's Quick
// Log / photo review (NutritionLogView) and the full Log Meal sheet
// (MealLoggingView) go through here, so every log lands the same way:
//
//   - an `.eaten` PlannedMeal (the canonical record every surface sums),
//     either filling the matching planned slot for that meal type (through
//     `MealOutcomeService.markEaten`: the planned dish is remembered so Undo /
//     Delete brings it back, later meals shift, the day rebalances), a second
//     log into an already-eaten PLAN slot as its own unplanned log (merging
//     only into an existing log), or as a new row attached to today's active
//     plan (or unbound when no plan covers today) — an "unplanned log" that
//     Undo / Delete removes;
//   - a legacy MealLog alongside it, linked from the meal so Undo / Delete
//     removes it too (no live reader needs it; no new readers should be added);
//   - `.tempoNutritionLogged` posted so the Dashboard re-pulls.
//
// The caller shows its success toast only after this returns without throwing.
//

import Foundation
import SwiftData

@MainActor
enum EatenMealRecorder {
    /// How to treat foods that already exist in an already-eaten meal.
    enum DuplicateResolution {
        /// Append everything — a second portion / new item.
        case add
        /// Replace existing foods with the same name, keep the rest.
        case edit
    }

    struct Result {
        /// The PlannedMeal that now holds the log.
        let meal: PlannedMeal
        /// Totals of the foods just logged (not the whole meal after a merge).
        let logged: MealMacros
    }

    // MARK: - Matching

    /// The planned slot a log of `type` eaten at `eatenAt` belongs to. Slots
    /// are matched by their NAME (a plan with 3, 4, 5 or 6 meals numbers its
    /// slots differently, so `mealNumber` alone put a Dinner log in the Snack
    /// slot); the closest scheduled time breaks ties between several slots of
    /// one type. Slots whose name carries no meal type ("Meal 3") fall back to
    /// the conventional number. A log never lands in a slot of another type —
    /// with no match it becomes its own unplanned log.
    static func matchingSlot(
        for type: MealType,
        eatenAt: Date,
        in todayMeals: [PlannedMeal],
        now: Date = Date()
    ) -> PlannedMeal? {
        // Supplement doses are never a slot a log can land in.
        let todayMeals = todayMeals.filter { !isSupplementDose($0) }
        var candidates = todayMeals.filter { MealType.inferred(fromName: $0.mealName) == type }
        if candidates.isEmpty {
            let targetMealNumber = type.sortOrder + 1
            candidates = todayMeals.filter {
                MealType.inferred(fromName: $0.mealName) == nil && $0.mealNumber == targetMealNumber
            }
        }
        // A plan slot always wins over a log sitting next to it (extra
        // portions are their own unplanned rows); logs only match each other.
        let planSlots = candidates.filter { !$0.isUnplannedLog }
        if !planSlots.isEmpty {
            candidates = planSlots
        }
        if candidates.count <= 1 {
            return candidates.first
        }
        return PlannedMealTimingMatcher.bestMatch(
            for: candidates,
            mealType: type.displayName,
            eatenAt: eatenAt,
            now: now
        )
    }

    /// Lowercased names in `foods` that already exist in the matched meal when
    /// that meal is already eaten. Non-empty → ask Add vs Edit.
    static func duplicateNames(
        of foods: [MealFoodItemInput],
        type: MealType,
        eatenAt: Date,
        in todayMeals: [PlannedMeal]
    ) -> [String] {
        guard let existing = matchingSlot(for: type, eatenAt: eatenAt, in: todayMeals),
              existing.status == .eaten
        else {
            return []
        }
        let existingNames = Set(existing.foods.map { $0.name.lowercased() })
        let dupes = foods.map { $0.name.lowercased() }.filter { existingNames.contains($0) }
        return Array(Set(dupes)).sorted()
    }

    // MARK: - Conversions

    /// A logged food as a logging input (one serving of its whole portion).
    static func input(from food: PlannedFood) -> MealFoodItemInput {
        MealFoodItemInput(
            foodId: UUID().uuidString,
            name: food.name,
            brand: nil,
            servings: 1,
            servingSize: food.quantityGrams,
            servingUnit: "g",
            calories: food.calories,
            proteinGrams: food.proteinG,
            carbsGrams: food.carbsG,
            fatGrams: food.fatG,
            source: .manual
        )
    }

    static func plannedFood(from item: MealFoodItemInput) -> PlannedFood {
        PlannedFood(
            name: item.name,
            quantityGrams: item.servingSize * item.servings,
            calories: item.totalCalories,
            proteinG: item.totalProtein,
            carbsG: item.totalCarbs,
            fatG: item.totalFat
        )
    }

    /// Inserts the legacy MealLog that mirrors a log.
    @discardableResult
    static func makeMealLog(
        items: [MealFoodItemInput],
        type: MealType,
        eatenAt: Date,
        source: MealSource,
        in context: ModelContext
    ) -> MealLog {
        let log = MealLog(
            type: type,
            dayDate: eatenAt,
            source: source,
            photo: nil,
            items: items.map { MealFoodItem(from: $0) }
        )
        log.loggedAt = eatenAt
        context.insert(log)
        return log
    }

    @discardableResult
    static func makeMealLog(
        foods: [PlannedFood],
        type: MealType,
        eatenAt: Date,
        source: MealSource,
        in context: ModelContext
    ) -> MealLog {
        makeMealLog(items: foods.map(input(from:)), type: type, eatenAt: eatenAt, source: source, in: context)
    }

    // MARK: - Supplement doses

    /// Name of the unplanned eaten entry a ticked supplement dose creates.
    static let supplementsMealName = "Supplements"

    /// True for the entry `recordSupplementDose` makes. Slot matching skips
    /// these so a log never lands in (or replaces) one, and one never fills
    /// a planned breakfast.
    static func isSupplementDose(_ meal: PlannedMeal) -> Bool {
        meal.mealName == supplementsMealName && meal.mealNumber == supplementMealNumber && meal.isUnplannedLog
    }

    private static let supplementMealNumber = 8

    /// Counts one supplement dose in `day`'s totals: its OWN unplanned eaten
    /// entry (frozen at a zero plan baseline, so it adds to "eaten" and never
    /// to the target; the weekly plan makes no room for it). Never touches a
    /// planned slot or the pantry. Inserts without saving — the caller saves
    /// (`SupplementIntakeStore`). Returns the entry's id for an exact undo.
    @discardableResult
    static func recordSupplementDose(
        name: String,
        macros: MealMacros,
        takenAt: Date = Date(),
        day: Date = Date(),
        id: UUID? = nil,
        in modelContext: ModelContext
    ) -> UUID {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let meal = PlannedMeal(
            dayDate: day,
            mealNumber: supplementMealNumber,
            mealName: supplementsMealName,
            scheduledTime: timeFormatter.string(from: takenAt),
            foods: [PlannedFood(
                name: name, quantityGrams: 0,
                calories: macros.calories, proteinG: macros.protein, carbsG: macros.carbs, fatG: macros.fat
            )],
            totalCalories: macros.calories,
            totalProtein: macros.protein,
            totalCarbs: macros.carbs,
            totalFat: macros.fat,
            status: .eaten,
            actualEatenAt: takenAt,
            mealPlan: Calendar.current.isDateInToday(day) ? activePlanCoveringToday(in: modelContext) : nil
        )
        if let id {
            meal.id = id
        }
        meal.markAsUnplannedLog()
        modelContext.insert(meal)
        return meal.id
    }

    /// Removes the entry a supplement tick created (untick). No-op when it is
    /// already gone (the user deleted it from the meal list).
    static func removeSupplementDose(mealID: UUID, in modelContext: ModelContext) {
        var descriptor = FetchDescriptor<PlannedMeal>(predicate: #Predicate<PlannedMeal> { $0.id == mealID })
        descriptor.fetchLimit = 1
        if let meal = try? modelContext.fetch(descriptor).first {
            modelContext.delete(meal)
        }
    }

    // MARK: - Record

    @discardableResult
    static func record(
        _ items: [MealFoodItemInput],
        type: MealType,
        eatenAt: Date,
        source: MealSource,
        resolution: DuplicateResolution = .add,
        origin: MealOrigin? = nil,
        deductPantry shouldDeduct: Bool = true,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil,
        now: Date = Date()
    ) throws -> Result {
        let todayMeals = CanonicalMeals.meals(on: now, in: modelContext)
        let plannedFoods = items.map(plannedFood(from:))
        let logged = MealMacros(
            calories: plannedFoods.reduce(0) { $0 + $1.calories },
            protein: plannedFoods.reduce(0) { $0 + $1.proteinG },
            carbs: plannedFoods.reduce(0) { $0 + $1.carbsG },
            fat: plannedFoods.reduce(0) { $0 + $1.fatG }
        )

        if let existing = matchingSlot(for: type, eatenAt: eatenAt, in: todayMeals, now: now) {
            if existing.status != .eaten {
                // First log for this slot — the logged foods REPLACE the
                // planned dish (remembered, so Undo / Delete brings it back)
                // and the log gets the same side effects as Mark Eaten:
                // later meals shift, the day rebalances, reminders cancel.
                let mealLog = makeMealLog(items: items, type: type, eatenAt: eatenAt, source: source, in: modelContext)
                do {
                    try MealOutcomeService.markEaten(
                        existing,
                        at: eatenAt,
                        replacingWith: plannedFoods,
                        mealLogID: mealLog.id,
                        pantry: origin == .kitchen && shouldDeduct ? .foods : .none,
                        env: MealOutcomeService.Env(modelContext: modelContext, notifications: notifications)
                    )
                } catch {
                    modelContext.rollback()
                    throw error
                }
                if let origin {
                    existing.origin = origin
                    try commit(modelContext)
                }
                return Result(meal: existing, logged: logged)
            }
            // Already eaten. A PLAN slot (not itself a log) must not absorb
            // extra foods: Undo / Delete would then "restore" the planned dish
            // plus the extras. A second portion becomes its own unplanned log
            // in the same meal type — removable on its own, the first log
            // untouched. An "edit" (replace same-named foods) does change the
            // slot's foods, so the planned dish is stashed first and Undo
            // still brings the ORIGINAL back.
            if !existing.isUnplannedLog, resolution == .add {
                return try recordUnplannedLog(
                    items: items, plannedFoods: plannedFoods, logged: logged,
                    type: type, eatenAt: eatenAt, source: source, origin: origin, deductPantry: shouldDeduct, now: now, in: modelContext
                )
            }
            // Whatever happens next rewrites the totals — keep the plan's
            // allocation for the daily target.
            existing.capturePlanBaselineIfNeeded()
            existing.stashPlannedDishIfNeeded()
            switch resolution {
            case .edit:
                let newNames = Set(plannedFoods.map { $0.name.lowercased() })
                let kept = existing.foods.filter { !newNames.contains($0.name.lowercased()) }
                existing.foods = kept + plannedFoods
                existing.recalculateTotals()
            case .add:
                existing.foods = existing.foods + plannedFoods
                existing.totalCalories += logged.calories
                existing.totalProtein += logged.protein
                existing.totalCarbs += logged.carbs
                existing.totalFat += logged.fat
            }
            existing.actualEatenAt = existing.actualEatenAt.map { min($0, eatenAt) } ?? eatenAt
            // Only a pure add takes stock off the pantry (just the NEW foods,
            // appended to what the meal already took). An edit rewrites foods
            // that were already counted, so it never deducts.
            var deducted: [PantryDecrementDetail] = []
            if origin == .kitchen, resolution == .add, shouldDeduct {
                deducted = deductPantry(for: plannedFoods, label: existing.mealName, appendingTo: existing, in: modelContext)
            }
            if let origin, resolution == .add, existing.origin == nil || origin == .kitchen {
                existing.origin = origin
            }
            syncMergedMealLog(
                of: existing, items: items, resolution: resolution,
                type: type, eatenAt: eatenAt, source: source, in: modelContext
            )
            do {
                try commit(modelContext)
            } catch {
                PantryDecrementService.creditExact(details: deducted, modelContext: modelContext)
                throw error
            }
            NotificationCenter.default.post(name: .tempoNutritionLogged, object: nil)
            return Result(meal: existing, logged: logged)
        }

        return try recordUnplannedLog(
            items: items, plannedFoods: plannedFoods, logged: logged,
            type: type, eatenAt: eatenAt, source: source, origin: origin, deductPantry: shouldDeduct, now: now, in: modelContext
        )
    }

    /// Takes `foods` off the pantry and records the exact per-row detail on
    /// `meal` (appending to any earlier detail) so Undo credits back exactly
    /// this. Handles depletions (grocery candidates) like Mark Eaten does.
    @discardableResult
    private static func deductPantry(
        for foods: [PlannedFood],
        label: String,
        appendingTo meal: PlannedMeal,
        in modelContext: ModelContext
    ) -> [PantryDecrementDetail] {
        let results = PantryDecrementService.decrement(foods: foods, label: label, modelContext: modelContext)
        meal.decrementDetail = meal.decrementDetail + results.flatMap(\.details)
        // A recorded (possibly empty) detail keeps Undo exact, never approximate.
        if meal.decrementDetailJSON == nil {
            meal.decrementDetailJSON = (try? JSONEncoder().encode([PantryDecrementDetail]()))
        }
        meal.didDecrementPantry = true
        PantryDepletionPlanCheck.handleDepletions(results, weeklyPlan: meal.mealPlan, modelContext: modelContext)
        return results.flatMap(\.details)
    }

    /// A log on top of the plan: its own eaten row (attached to today's
    /// active plan, or unbound), frozen at a zero baseline so it adds to
    /// "eaten" but never to the day's target. Undo / Delete removes it.
    private static func recordUnplannedLog(
        items: [MealFoodItemInput],
        plannedFoods: [PlannedFood],
        logged: MealMacros,
        type: MealType,
        eatenAt: Date,
        source: MealSource,
        origin: MealOrigin?,
        deductPantry shouldDeduct: Bool = true,
        now: Date,
        in modelContext: ModelContext
    ) throws -> Result {
        let mealLog = makeMealLog(items: items, type: type, eatenAt: eatenAt, source: source, in: modelContext)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let created = PlannedMeal(
            dayDate: now,
            mealNumber: type.sortOrder + 1,
            mealName: type.displayName,
            scheduledTime: timeFormatter.string(from: eatenAt),
            foods: plannedFoods,
            totalCalories: logged.calories,
            totalProtein: logged.protein,
            totalCarbs: logged.carbs,
            totalFat: logged.fat,
            status: .eaten,
            linkedMealLogID: mealLog.id,
            actualEatenAt: eatenAt,
            mealPlan: activePlanCoveringToday(in: modelContext)
        )
        // Not something the plan asked for → adds to "eaten", never to
        // the target.
        created.markAsUnplannedLog()
        created.origin = origin
        modelContext.insert(created)
        var deducted: [PantryDecrementDetail] = []
        if origin == .kitchen, shouldDeduct {
            deducted = deductPantry(for: plannedFoods, label: created.mealName, appendingTo: created, in: modelContext)
        }
        do {
            try commit(modelContext)
        } catch {
            // The deduction saved on its own; a log that never landed must not keep it.
            PantryDecrementService.creditExact(details: deducted, modelContext: modelContext)
            throw error
        }
        // Tell the Dashboard (separate VM) to re-pull its Fuel quadrant so
        // its calories + eat-times match the Nutrition tab immediately.
        NotificationCenter.default.post(name: .tempoNutritionLogged, object: nil)
        return Result(meal: created, logged: logged)
    }

    private static func commit(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Keeps the single legacy MealLog linked from a meal in step with a
    /// merge, so deleting the meal removes everything it logged. A meal with
    /// no linked log (a plain Mark Eaten) gets one.
    private static func syncMergedMealLog(
        of meal: PlannedMeal,
        items: [MealFoodItemInput],
        resolution: DuplicateResolution,
        type: MealType,
        eatenAt: Date,
        source: MealSource,
        in context: ModelContext
    ) {
        if let logID = meal.linkedMealLogID {
            var descriptor = FetchDescriptor<MealLog>(predicate: #Predicate<MealLog> { $0.id == logID })
            descriptor.fetchLimit = 1
            if let log = try? context.fetch(descriptor).first {
                if resolution == .edit {
                    let names = Set(items.map { $0.name.lowercased() })
                    for item in log.items where names.contains(item.name.lowercased()) {
                        context.delete(item)
                    }
                    log.items.removeAll { names.contains($0.name.lowercased()) }
                }
                log.items.append(contentsOf: items.map { MealFoodItem(from: $0) })
                log.recalculateTotals()
                log.loggedAt = min(log.loggedAt, eatenAt)
                return
            }
        }
        meal.linkedMealLogID = makeMealLog(items: items, type: type, eatenAt: eatenAt, source: source, in: context).id
    }

    /// The active plan that covers today — the same plan Nutrition Today
    /// shows. nil when none does (the log is then unbound).
    static func activePlanCoveringToday(in context: ModelContext) -> WeeklyMealPlan? {
        let descriptor = FetchDescriptor<WeeklyMealPlan>(
            predicate: #Predicate<WeeklyMealPlan> { $0.isActive == true },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).first { $0.coversToday }
    }

    // MARK: - Helpers

    /// Default meal type for a log at `date`, by local time of day. Tighter
    /// breakfast window (at 10:30 most people are logging lunch); late
    /// evening defaults to snack. The user can always change it.
    nonisolated static func defaultMealType(for date: Date = Date()) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5 ..< 10: return .breakfast
        case 10 ..< 16: return .lunch
        case 18 ..< 22: return .dinner
        default: return .snack
        }
    }

    /// Best-effort grams from a serving-size string. Returns the amount only
    /// when a number is directly followed by a mass/volume unit — g, gr, gram(s),
    /// kg, oz, lb(s), ml (1 ml ≈ 1 g), cl/dl/l, fl oz — anywhere in the string
    /// ("250g", "330 ml", "1 cup (240 ml)", "3.5 oz"). Everything else yields 0:
    /// "2 eggs", "1 large bowl", "1 serving", "1 cup", "diced". The old check
    /// was `contains("g")`, which made "2 eggs" and "1 serving" read as 2 g /
    /// 1 g and sent the portion editor's per-gram maths 100× off.
    /// quantityGrams is cosmetic for the log, but the portion editor derives
    /// per-gram density from it, so an unknown amount MUST be 0 (servings mode).
    nonisolated static func gramsFromServingSize(_ serving: String) -> Double {
        let lower = serving.lowercased()
        let pattern = #"(?<![\w.])(\d+(?:[.,]\d+)?)\s*(fl\.?\s*oz|kg|lbs?|oz|ml|cl|dl|liters?|litres?|l|grams?|gr|g)(?![a-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let numberRange = Range(match.range(at: 1), in: lower),
              let unitRange = Range(match.range(at: 2), in: lower),
              let number = Double(lower[numberRange].replacingOccurrences(of: ",", with: "."))
        else {
            return 0
        }
        let unit = lower[unitRange].filter { !$0.isWhitespace && $0 != "." }
        let factor: Double = switch unit {
        case "kg": 1000
        case "oz": 28.3495
        case "lb", "lbs": 453.592
        case "floz": 29.5735
        case "cl": 10
        case "dl": 100
        case "l", "liter", "liters", "litre", "litres": 1000
        default: 1 // g, gr, gram(s), ml
        }
        return number * factor
    }
}

// MARK: - MealType inference

extension MealType {
    /// The meal type a slot name stands for ("Breakfast", "Afternoon snack",
    /// "Post-workout snack", "Supper"). nil when the name carries none
    /// ("Meal 3"). Snack wins over the others ("Pre-dinner snack").
    nonisolated static func inferred(fromName name: String) -> MealType? {
        let lower = name.lowercased()
        if lower.contains("snack") {
            return .snack
        }
        if lower.contains("breakfast") || lower.contains("brunch") {
            return .breakfast
        }
        if lower.contains("lunch") {
            return .lunch
        }
        if lower.contains("dinner") || lower.contains("supper") {
            return .dinner
        }
        return nil
    }
}
