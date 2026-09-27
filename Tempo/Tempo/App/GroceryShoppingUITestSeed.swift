//
// GroceryShoppingUITestSeed.swift
// Tempo
//
// Advanced-groceries UI test fixture — DEBUG-only, no-ops unless launched
// with its launch argument (see GuidedRunUITestSeed for the established
// pattern this follows). A UI test can't generate a real week's plan,
// wait for the AI price-estimate round trip, or rack up real
// PantryPriceEntry history, so this seeds a ready-to-screenshot grocery
// list directly: items across every aisle category, a couple already
// checked (so the Done-Shopping review sheet has rows to show), one
// manual item, Publix selected as the active store, a budget cap set
// LOW enough to exercise the over-budget banner, and prices resolved
// through the SAME two real sources the app itself reads (a
// PantryPriceEntry for "paid" rows, the local GroceryPriceCache for
// "estimate"/approx rows) — so no network round trip is needed and
// nothing here bypasses the real pricing code path.
//

import Foundation
import SwiftData

#if DEBUG
    enum GroceryShoppingUITestSeed {
        static let launchArgument = "--uitesting-grocery-shopping-sample"

        @MainActor
        static func seedIfRequested(context: ModelContext) {
            guard ProcessInfo.processInfo.arguments.contains(launchArgument) else {
                return
            }

            let calendar = Calendar.current
            let weekStart = calendar.startOfDay(for: Date())
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

            let plan = WeeklyMealPlan(startDate: weekStart, endDate: weekEnd)
            context.insert(plan)

            let list = GroceryList(weekStartDate: weekStart, sourceMealPlanID: plan.id)
            context.insert(list)

            // canonicalName, displayName, quantity, unit, category, isChecked, isManual
            let rows: [(String, String, Double, PantryUnit, String, Bool, Bool)] = [
                ("chicken breast", "Chicken Breast", 900, .grams, "meat", true, false),
                ("broccoli", "Broccoli", 3, .pieces, "produce", true, false),
                ("salmon", "Salmon", 2, .pieces, "seafood", false, false),
                ("rice", "Rice", 1, .packs, "grains", false, false),
                ("milk", "Milk", 1, .liters, "dairy", false, false),
                ("frozen peas", "Frozen Peas", 1, .packs, "frozen", false, false),
                ("olive oil", "Olive Oil", 1, .bottles, "oils", false, true),
                ("black beans", "Canned Black Beans", 2, .cans, "pantry", false, false),
            ]

            var items: [GroceryListItem] = []
            for row in rows {
                items.append(GroceryListItem(
                    list: list,
                    canonicalFoodName: row.0,
                    displayName: row.1,
                    quantity: row.2,
                    unit: row.3,
                    category: row.4,
                    isChecked: row.5,
                    isManual: row.6
                ))
            }
            list.items = items
            for item in items {
                context.insert(item)
            }

            // "Paid" rows — real PantryPriceEntry history at Publix, same
            // quantity/unit as the line item so the ratio math is exact.
            let paidRows: [(String, String, Double, PantryUnit, Double)] = [
                ("chicken breast", "Chicken Breast", 900, .grams, 8.50),
                ("broccoli", "Broccoli", 3, .pieces, 2.50),
            ]
            for row in paidRows {
                let entry = PantryPriceEntry(
                    canonicalFoodName: row.0,
                    displayName: row.1,
                    purchaseDate: Date(),
                    totalPaidUSD: row.4,
                    quantity: row.2,
                    unit: row.3,
                    store: "Publix"
                )
                context.insert(entry)
            }
            try? context.save()

            // "Estimate"/approx rows — a warmed local price cache, exactly
            // what a prior AI batch call would have written.
            var cache = GroceryPriceCache.load()
            let estimateRows: [(String, Double)] = [
                ("salmon", 11.00),
                ("rice", 4.25),
                ("milk", 3.20),
                ("frozen peas", 2.10),
                ("olive oil", 7.99),
                ("black beans", 1.80),
            ]
            for (name, usd) in estimateRows {
                cache.set(store: .publix, canonicalName: name, usd: usd)
            }
            cache.save()

            // Publix selected, budget cap set low enough (sum ≈ $41) to
            // show the over-budget banner + "Cheaper swaps" entry point.
            let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first ?? {
                let created = UserSettings()
                context.insert(created)
                return created
            }()
            settings.groceryActiveStore = .publix
            settings.groceryBudgetCapUSD = 35
            try? context.save()
        }
    }
#endif
