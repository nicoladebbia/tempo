//
// NutritionPlanUITestSeed.swift
// Tempo
//
// Nutrition QA fixture — DEBUG-only, no-ops unless launched with its launch
// argument (same pattern as GroceryShoppingUITestSeed). A simulator can't
// build a real week (that needs the AI backend), so this seeds one the way
// the generator saves it: an active plan for the current Monday–Sunday with
// four meals a day, earlier days already eaten, a pantry with part-used
// packs, and a grocery list built by the real LocalGroceryListService — so
// eat / skip / undo / delete, past-day logs, pantry fractions and the list
// can be checked on screen. Seeds once per store (a relaunch keeps whatever
// the tester did).
//

import Foundation
import SwiftData

#if DEBUG
    enum NutritionPlanUITestSeed {
        static let launchArgument = "--uitesting-nutrition-plan-sample"

        @MainActor
        static func seedIfRequested(context: ModelContext) {
            ReceiptUITestSeed.seedIfRequested(context: context)
            guard ProcessInfo.processInfo.arguments.contains(launchArgument) else {
                return
            }
            let existing = (try? context.fetch(FetchDescriptor<WeeklyMealPlan>(
                predicate: #Predicate { $0.isActive }
            ))) ?? []
            guard existing.isEmpty else {
                return
            }

            let calendar = Calendar.current
            let weekStart = WeeklyPlanService.currentWeekStart()
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            var dayTypes: [Int: String] = [:]
            for key in 1 ... 7 {
                dayTypes[key] = [1, 3, 5].contains(key) ? DayType.strength.rawValue : DayType.rest.rawValue
            }
            let plan = WeeklyMealPlan(startDate: weekStart, endDate: weekEnd, dayTypeAssignments: dayTypes)
            context.insert(plan)

            let today = calendar.startOfDay(for: Date())
            for offset in 0 ..< 7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                    continue
                }
                for (index, template) in templates.enumerated() {
                    let meal = PlannedMeal(
                        dayDate: day,
                        mealNumber: index + 1,
                        mealName: template.name,
                        scheduledTime: template.time,
                        foods: template.foods,
                        totalCalories: template.foods.reduce(0) { $0 + $1.calories },
                        totalProtein: template.foods.reduce(0) { $0 + $1.proteinG },
                        totalCarbs: template.foods.reduce(0) { $0 + $1.carbsG },
                        totalFat: template.foods.reduce(0) { $0 + $1.fatG },
                        mealPlan: plan
                    )
                    // Days before today: eaten, except Monday's snack (skipped).
                    if day < today {
                        meal.status = template.name == "Snack" && offset == 0 ? .skipped : .eaten
                        if meal.status == .eaten {
                            meal.actualEatenAt = day.addingTimeInterval(Double(8 + index * 4) * 3600)
                        }
                    }
                    context.insert(meal)
                }
            }

            let pantry = LocalPantryService(modelContext: context)
            let stock: [(String, Double, PantryUnit)] = [
                ("Pasta", 1, .packs),
                ("Rice", 0.6, .packs),
                ("Eggs", 6, .pieces),
                ("Oats", 300, .grams),
            ]
            for (name, quantity, unit) in stock {
                _ = try? pantry.mergeOrCreate(
                    rawName: name, quantity: quantity, unit: unit, storageLocation: .pantry,
                    purchaseDate: Date(), purchaseSource: .manual, sourceReceiptLineItemID: nil
                )
            }
            try? context.save()
            _ = try? LocalGroceryListService(modelContext: context).generate(
                from: plan, pantry: pantry, weekStartDate: weekStart
            )
            try? context.save()
        }

        private struct Template {
            let name: String
            let time: String
            let foods: [PlannedFood]
        }

        private static let templates: [Template] = [
            Template(name: "Breakfast", time: "08:00", foods: [
                PlannedFood(name: "Oats", quantityGrams: 80, calories: 311, proteinG: 13.5, carbsG: 53, fatG: 5.5),
                PlannedFood(name: "Eggs", quantityGrams: 100, calories: 155, proteinG: 13, carbsG: 1.1, fatG: 11),
            ]),
            Template(name: "Lunch", time: "13:00", foods: [
                PlannedFood(name: "Chicken breast", quantityGrams: 200, calories: 330, proteinG: 62, carbsG: 0, fatG: 7.2),
                PlannedFood(name: "Rice", quantityGrams: 200, calories: 260, proteinG: 5.4, carbsG: 56, fatG: 0.6),
            ]),
            Template(name: "Snack", time: "16:30", foods: [
                PlannedFood(name: "Greek yogurt", quantityGrams: 200, calories: 194, proteinG: 20, carbsG: 7.8, fatG: 10),
            ]),
            Template(name: "Dinner", time: "19:30", foods: [
                PlannedFood(name: "Salmon", quantityGrams: 180, calories: 374, proteinG: 36, carbsG: 0, fatG: 24),
                PlannedFood(name: "Pasta", quantityGrams: 100, calories: 371, proteinG: 13, carbsG: 75, fatG: 1.5),
            ]),
        ]
    }
#endif
