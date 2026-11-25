//
// SpendingScenarioSeed.swift
// Tempo
//
// `sim.sh qa --local --scenario spending`: eight weeks of grocery spend to
// look at on the Spending page. Confirmed receipts spread over the weeks (one
// week over the budget), a manual purchase, one receipt waiting for review and
// one that failed to read. DEBUG only, written through the real models.
//

import Foundation
import SwiftData

#if DEBUG
    enum SpendingScenarioSeed {
        /// The weekly budget the scenario sets. Weeks above it show as over.
        static let budgetCapUSD = 120

        @MainActor
        static func seed(context: ModelContext, now: Date) {
            var calendar = Calendar.current
            calendar.firstWeekday = 2
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)

            // Weeks back from this one: (store, days into the week, total, lines).
            let confirmed: [(week: Int, store: String, day: Int, total: Double, lines: Int)] = [
                (7, "Publix", 1, 96.40, 24), (6, "Trader Joe's", 2, 78.15, 18), (6, "Publix", 5, 41.20, 9),
                (5, "Publix", 0, 112.80, 31), (4, "Walmart", 3, 134.55, 38), (3, "Publix", 1, 88.30, 22),
                (2, "Publix", 2, 101.75, 27), (1, "Aldi", 4, 64.90, 16), (1, "Publix", 6, 52.10, 12),
                (0, "Publix", 0, 73.45, 19),
            ]
            for row in confirmed {
                let date = day(row.day, ofWeek: row.week, from: thisWeek, calendar: calendar, notAfter: now)
                let receipt = Receipt(
                    store: row.store, purchaseDate: date, totalAmount: row.total,
                    ocrStatus: .confirmed, userReviewed: true
                )
                context.insert(receipt)
                for index in 0 ..< row.lines {
                    let line = ReceiptLineItem(
                        receipt: receipt, rawText: "ITEM \(index + 1)", canonicalFoodName: "item \(index + 1)",
                        displayName: "Item \(index + 1)", quantity: 1, unit: .each,
                        totalPrice: row.total / Double(row.lines), userConfirmed: true
                    )
                    context.insert(line)
                }
            }

            // A receipt scanned this week that still needs a look, and one that failed.
            let waiting = Receipt(
                store: "Publix", purchaseDate: day(1, ofWeek: 0, from: thisWeek, calendar: calendar, notAfter: now),
                totalAmount: 61.37, ocrStatus: .awaitingReview
            )
            context.insert(waiting)
            context.insert(ReceiptLineItem(
                receipt: waiting, rawText: "GV WHL MILK GAL", canonicalFoodName: "milk", displayName: "Whole milk",
                quantity: 1, unit: .each, totalPrice: 3.89
            ))
            context.insert(Receipt(
                store: "", purchaseDate: day(0, ofWeek: 0, from: thisWeek, calendar: calendar, notAfter: now),
                totalAmount: 0, ocrStatus: .failed
            ))

            // A purchase typed in by hand (counts toward its week like a receipt).
            context.insert(PantryPriceEntry(
                canonicalFoodName: "olive oil", displayName: "Olive oil",
                purchaseDate: day(2, ofWeek: 3, from: thisWeek, calendar: calendar, notAfter: now),
                totalPaidUSD: 14.50, quantity: 1, unit: .bottles, store: "Costco"
            ))

            let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first ?? {
                let created = UserSettings()
                context.insert(created)
                return created
            }()
            settings.groceryBudgetCapUSD = budgetCapUSD
        }

        /// `offset` days into the week that started `weeksBack` weeks before `thisWeek`, never in the future.
        private static func day(_ offset: Int, ofWeek weeksBack: Int, from thisWeek: Date, calendar: Calendar, notAfter now: Date) -> Date {
            let start = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: thisWeek) ?? thisWeek
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            return min(date, now)
        }
    }
#endif
