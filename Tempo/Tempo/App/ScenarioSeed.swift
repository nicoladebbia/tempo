//
// ScenarioSeed.swift
// Tempo
//
// Named starting states for `scripts/sim.sh qa --local --scenario <name>`
// (DEBUG only; no-ops without `--uitesting-scenario <name>`). sim.sh wipes
// the app first and signs the simulator into its test account on the local
// test backend (scripts/testenv.sh), so each scenario starts from the same
// place every time. On-device rows are written through the same models the
// app uses; anything the server owns (the weekly plan) is requested from
// the real server path after launch, so push → sync → save runs for real.
//
// `sim.sh scenarios` lists the `case "name": // description` lines below,
// so keep that shape when adding one.
//

import Foundation
import SwiftData

#if DEBUG
    enum ScenarioSeed {
        static let launchArgument = "--uitesting-scenario"

        static var requested: String? {
            let args = ProcessInfo.processInfo.arguments
            guard let index = args.firstIndex(of: launchArgument), index + 1 < args.count else {
                return nil
            }
            return args[index + 1]
        }

        /// Seed once per install: relaunching from the home screen (no
        /// launch arguments) or a second ⌘R must not duplicate rows.
        private static let seededKey = "tempo.scenario.seeded"

        @MainActor
        static func seedIfRequested(context: ModelContext) {
            guard let name = requested, UserDefaults.standard.string(forKey: seededKey) != name else {
                return
            }
            seed(name, context: context)
            UserDefaults.standard.set(name, forKey: seededKey)
        }

        @MainActor
        static func seed(_ name: String, context: ModelContext) {
            switch name {
            case "fresh": // brand-new account, onboarding from the first screen
                break
            case "fuel-ready": // onboarded, Fuel set up, stocked pantry — ready to build a week
                fuelReady(context)
            case "week": // fuel-ready + this week's plan built by the local server (push → sync)
                fuelReady(context)
            case "groceries": // fuel-ready + a grocery list over budget, some items checked
                fuelReady(context)
                GroceryShoppingUITestSeed.seed(context: context)
            case "eaten-before-update": // meals marked eaten by an old build (no undo detail) — test undo
                fuelReady(context)
                eatenBeforeUpdate(context)
            case "training": // onboarded + trainer program with a guided run today
                onboarded(context)
                GuidedRunUITestSeed.seed(context: context)
            case "edge": // long names, emoji, zero and huge numbers everywhere
                fuelReady(context)
                edge(context)
            default:
                print("[ScenarioSeed] unknown scenario '\(name)' — run scripts/sim.sh scenarios")
            }
            try? context.save()
        }

        /// After the main tab view appears, with services and a signed-in
        /// session. Only "week" needs the server.
        @MainActor
        static func afterLaunch(modelContext: ModelContext, deps: PlanDeps) async {
            guard requested == "week" else {
                return
            }
            let weekStart = WeeklyPlanService.weekStart()
            let start = weekStart
            let existing = (try? modelContext.fetch(FetchDescriptor<WeeklyMealPlan>(
                predicate: #Predicate { $0.startDate == start && $0.isActive }
            ))) ?? []
            guard existing.isEmpty else {
                return
            }
            do {
                // Same request the Sunday check-in makes. The server pushes
                // "plan ready" and the push handler syncs it in; polling here
                // too means the scenario still lands if the push is missed.
                _ = try await WeeklyPlanService.shared.buildNow(weekStart: weekStart, modelContext: modelContext, deps: deps)
            } catch {
                print("[ScenarioSeed] week build failed: \(error)")
            }
        }

        // MARK: - Pieces

        @MainActor
        private static func onboarded(_ context: ModelContext) {
            UserDefaults.standard.set(true, forKey: "tempo.onboarding.complete")
            if (try? context.fetch(FetchDescriptor<UserSettings>()))?.isEmpty ?? true {
                context.insert(UserSettings())
            }
        }

        @MainActor
        private static func fuelReady(_ context: ModelContext) {
            onboarded(context)
            var routine = WeeklyRoutine(days: (1 ... 7).map { DayRoutine(weekday: $0) })
            for weekday in 1 ... 7 {
                var day = routine[weekday]
                day.wakeMinutes = weekday <= 5 ? 7 * 60 : 9 * 60
                day.bedMinutes = 23 * 60
                if [1, 2, 4, 5].contains(weekday) {
                    day.training = TrainingSlot(startMinutes: 17 * 60 + 30, durationMinutes: 75, kind: "gym")
                }
                routine[weekday] = day
            }
            var draft = FuelSetupDraft()
            draft.weightKg = 82
            draft.heightCm = 183
            draft.age = 22
            draft.sex = .male
            draft.goal = .leanGain
            draft.goalWeightKg = 85
            draft.weeklyRateKg = 0.25
            draft.mealsPerDay = 4
            draft.cookingSkill = .intermediate
            draft.cookMinutesWeekday = 30
            draft.cookMinutesWeekend = 60
            draft.weeklyBudgetUSD = 90
            draft.stores = ["Publix"]
            draft.dislikedFoods = ["mushrooms"]
            draft.routine = routine
            draft.save(to: context)

            pantry(context, [
                ("chicken breast", "Chicken Breast", 1200, .grams, .fridge),
                ("white rice", "White Rice", 2000, .grams, .pantry),
                ("oats", "Rolled Oats", 1000, .grams, .pantry),
                ("eggs", "Eggs", 12, .pieces, .fridge),
                ("greek yogurt", "Greek Yogurt", 1000, .grams, .fridge),
                ("broccoli", "Broccoli", 500, .grams, .fridge),
                ("olive oil", "Olive Oil", 1, .bottles, .cupboard),
                ("banana", "Bananas", 6, .pieces, .pantry),
            ])
        }

        /// The undo-after-update bug: an old build marked meals eaten and
        /// took the food out of the pantry without saving what it took.
        @MainActor
        private static func eatenBeforeUpdate(_ context: ModelContext) {
            let calendar = Calendar.current
            let weekStart = WeeklyPlanService.weekStart()
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let plan = WeeklyMealPlan(startDate: weekStart, endDate: weekEnd)
            context.insert(plan)
            let today = Date()
            let meals: [(Int, String, String, [PlannedFood], MealStatus)] = [
                (1, "Breakfast", "08:00", [
                    PlannedFood(name: "oats", quantityGrams: 80, calories: 303, proteinG: 10.6, carbsG: 54, fatG: 5.3),
                    PlannedFood(name: "greek yogurt", quantityGrams: 200, calories: 194, proteinG: 20, carbsG: 7.2, fatG: 10),
                ], .eaten),
                (2, "Lunch", "12:30", [
                    PlannedFood(name: "chicken breast", quantityGrams: 180, calories: 297, proteinG: 55.8, carbsG: 0, fatG: 6.5),
                    PlannedFood(name: "white rice", quantityGrams: 220, calories: 286, proteinG: 5.9, carbsG: 62, fatG: 0.6),
                ], .eaten),
                (3, "Dinner", "19:30", [
                    PlannedFood(name: "chicken breast", quantityGrams: 180, calories: 297, proteinG: 55.8, carbsG: 0, fatG: 6.5),
                    PlannedFood(name: "broccoli", quantityGrams: 150, calories: 51, proteinG: 4.2, carbsG: 10, fatG: 0.6),
                ], .planned),
            ]
            for (number, name, time, foods, status) in meals {
                let meal = PlannedMeal(
                    dayDate: today,
                    mealNumber: number,
                    mealName: name,
                    scheduledTime: time,
                    foods: foods,
                    totalCalories: foods.reduce(0) { $0 + $1.calories },
                    totalProtein: foods.reduce(0) { $0 + $1.proteinG },
                    totalCarbs: foods.reduce(0) { $0 + $1.carbsG },
                    totalFat: foods.reduce(0) { $0 + $1.fatG },
                    status: status,
                    actualEatenAt: status == .eaten ? today : nil,
                    mealPlan: plan
                )
                if status == .eaten {
                    meal.didDecrementPantry = true
                    meal.decrementDetailJSON = nil
                }
                context.insert(meal)
            }
            // Pantry already reflects what those two meals used.
            let used: [String: Double] = ["oats": 80, "greek yogurt": 200, "chicken breast": 180, "white rice": 220]
            for item in (try? context.fetch(FetchDescriptor<PantryItem>())) ?? [] {
                if let amount = used[item.canonicalName] {
                    item.quantity -= amount
                }
            }
        }

        @MainActor
        private static func edge(_ context: ModelContext) {
            pantry(context, [
                (
                    "extra virgin cold pressed organic unfiltered olive oil from a small family farm in puglia",
                    "Extra Virgin Cold-Pressed Organic Unfiltered Olive Oil From A Small Family Farm In Puglia 🫒",
                    1,
                    .bottles,
                    .cupboard
                ),
                ("salt", "Salt 🧂", 0, .grams, .cupboard),
                ("rice", "Rice (bulk)", 99999, .grams, .pantry),
                ("jalapeno", "Jalapeño “hot” — très piquant ✨", 3, .pieces, .fridge),
            ])
            let weekStart = WeeklyPlanService.weekStart()
            let plan = WeeklyMealPlan(
                startDate: weekStart,
                endDate: Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            )
            context.insert(plan)
            let foods = [
                PlannedFood(name: "rice", quantityGrams: 5000, calories: 6500, proteinG: 135, carbsG: 1400, fatG: 15),
                PlannedFood(name: "salt", quantityGrams: 0, calories: 0, proteinG: 0, carbsG: 0, fatG: 0),
            ]
            context.insert(PlannedMeal(
                dayDate: Date(),
                mealNumber: 1,
                mealName: "A very long meal name that should wrap or truncate cleanly on the smallest iPhone 🍚🍚🍚",
                scheduledTime: "00:00",
                foods: foods,
                totalCalories: 6500,
                totalProtein: 135,
                totalCarbs: 1400,
                totalFat: 15,
                mealPlan: plan
            ))
            context.insert(PlannedMeal(
                dayDate: Date(),
                mealNumber: 2,
                mealName: "Empty",
                scheduledTime: "23:59",
                mealPlan: plan
            ))
        }

        @MainActor
        private static func pantry(
            _ context: ModelContext,
            _ rows: [(String, String, Double, PantryUnit, PantryStorageLocation)]
        ) {
            for row in rows {
                context.insert(PantryItem(
                    canonicalName: row.0,
                    displayName: row.1,
                    quantity: row.2,
                    unit: row.3,
                    storageLocation: row.4,
                    purchaseDate: Date()
                ))
            }
        }
    }
#endif
