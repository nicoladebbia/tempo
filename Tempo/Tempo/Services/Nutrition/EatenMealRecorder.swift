//
// EatenMealRecorder.swift
// Tempo
//
// The one write path for "the user ate these foods". Both the Log tab's Quick
// Log / photo review (NutritionLogView) and the full Log Meal sheet
// (MealLoggingView) go through here, so every log lands the same way:
//
//   - an `.eaten` PlannedMeal (the canonical record every surface sums),
//     either filling the matching planned slot for that meal type, merging
//     into an already-eaten one, or as a new row attached to today's active
//     plan (or unbound when no plan covers today);
//   - a legacy MealLog alongside it (still read by a few older surfaces —
//     no new readers should be added);
//   - pending reminders for a filled planned slot cancelled;
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

    /// The planned slot a log of `type` eaten at `eatenAt` belongs to: meals
    /// with that type's slot number, disambiguated by closest scheduled time.
    static func matchingSlot(
        for type: MealType,
        eatenAt: Date,
        in todayMeals: [PlannedMeal],
        now: Date = Date()
    ) -> PlannedMeal? {
        let targetMealNumber = type.sortOrder + 1
        let candidates = todayMeals.filter { $0.mealNumber == targetMealNumber }
        if candidates.count == 1 {
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

    // MARK: - Record

    @discardableResult
    static func record(
        _ items: [MealFoodItemInput],
        type: MealType,
        eatenAt: Date,
        source: MealSource,
        resolution: DuplicateResolution = .add,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)? = nil,
        now: Date = Date()
    ) throws -> Result {
        let todayMeals = CanonicalMeals.meals(on: now, in: modelContext)
        let plannedFoods = items.map { item in
            PlannedFood(
                name: item.name,
                quantityGrams: item.servingSize * item.servings,
                calories: item.totalCalories,
                proteinG: item.totalProtein,
                carbsG: item.totalCarbs,
                fatG: item.totalFat
            )
        }
        let logged = MealMacros(
            calories: plannedFoods.reduce(0) { $0 + $1.calories },
            protein: plannedFoods.reduce(0) { $0 + $1.proteinG },
            carbs: plannedFoods.reduce(0) { $0 + $1.carbsG },
            fat: plannedFoods.reduce(0) { $0 + $1.fatG }
        )

        let mealLog = MealLog(
            type: type,
            dayDate: now,
            source: source,
            photo: nil,
            items: items.map { MealFoodItem(from: $0) }
        )
        mealLog.loggedAt = eatenAt
        modelContext.insert(mealLog)

        let meal: PlannedMeal
        var filledPlannedSlot = false
        if let existing = matchingSlot(for: type, eatenAt: eatenAt, in: todayMeals, now: now) {
            // Whatever happens next rewrites the totals — keep the plan's
            // allocation for the daily target.
            existing.capturePlanBaselineIfNeeded()
            if existing.status == .eaten {
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
            } else {
                // First log for this slot — the logged foods replace the
                // planned dish.
                filledPlannedSlot = existing.status == .planned
                existing.foods = plannedFoods
                existing.totalCalories = logged.calories
                existing.totalProtein = logged.protein
                existing.totalCarbs = logged.carbs
                existing.totalFat = logged.fat
                existing.status = .eaten
                existing.linkedMealLogID = mealLog.id
                existing.actualEatenAt = eatenAt
            }
            meal = existing
        } else {
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
            modelContext.insert(created)
            meal = created
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        if filledPlannedSlot {
            notifications?.cancelOverdueMealReminder(forMealID: meal.id)
            notifications?.cancelPrepStartReminder(forMealID: meal.id)
            notifications?.cancelDefrostReminders(forMealID: meal.id)
        }
        // Tell the Dashboard (separate VM) to re-pull its Fuel quadrant so
        // its calories + eat-times match the Nutrition tab immediately.
        NotificationCenter.default.post(name: .tempoNutritionLogged, object: nil)
        return Result(meal: meal, logged: logged)
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

    /// Best-effort grams from a serving-size string. Returns the leading
    /// number only when the unit is grams ("250g", "250 g"); anything else
    /// ("1 cup", "diced", "medium") yields 0 — quantityGrams is cosmetic
    /// (drives serving-size display only), so a 0 doesn't affect macros.
    nonisolated static func gramsFromServingSize(_ serving: String) -> Double {
        let lower = serving.lowercased()
        guard lower.contains("g") else {
            return 0
        }
        let number = lower.prefix { $0.isNumber || $0 == "." }
        return Double(number) ?? 0
    }
}
