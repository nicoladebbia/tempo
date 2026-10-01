//
// GroceryWeeklySpend.swift
// Tempo
//
// Weekly spend history (BUILD item 4): actual spend per week from
// PantryPriceEntry (manual/grocery-confirm purchases) + Receipt totals
// (receipt-scan purchases), compared against the budget cap, for the last
// N weeks. Pure/static — no SwiftData fetches here, callers pass in the
// already-fetched rows.
//

import Foundation

// MARK: - GroceryWeeklySpend

struct GroceryWeeklySpend: Identifiable, Equatable {
    /// Monday of the week (startOfDay), used as a stable id.
    let weekStartDate: Date
    let totalUSD: Double
    let budgetCapUSD: Int?

    var id: Date {
        weekStartDate
    }

    var isOverBudget: Bool {
        guard let budgetCapUSD else {
            return false
        }
        return totalUSD > Double(budgetCapUSD)
    }
}

// MARK: - GroceryWeeklySpendCalculator

enum GroceryWeeklySpendCalculator {
    /// Buckets `priceEntries` + `receipts` into calendar weeks (Monday
    /// start) and sums their totals, for the last `weeks` weeks INCLUDING
    /// the current one. `PantryPriceEntry` rows sourced from a receipt scan
    /// are excluded when `receipts` already covers that spend, to avoid
    /// double-counting — matched by `sourceReceiptLineItemID` being non-nil.
    static func compute(
        priceEntries: [PantryPriceEntry],
        receipts: [Receipt],
        weeks: Int = 8,
        budgetCapUSD: Int?,
        now: Date = Date(),
        calendar baseCalendar: Calendar = .current
    ) -> [GroceryWeeklySpend] {
        guard weeks > 0 else {
            return []
        }
        // Monday weeks like the grocery lists, whatever the locale's first
        // weekday (US = Sunday, which split a Sat+Sun shop across two bars).
        var calendar = baseCalendar
        calendar.firstWeekday = 2

        func weekStart(for date: Date) -> Date {
            let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            return calendar.startOfDay(for: interval?.start ?? date)
        }

        let currentWeekStart = weekStart(for: now)
        guard let earliestWeekStart = calendar.date(
            byAdding: .weekOfYear, value: -(weeks - 1), to: currentWeekStart
        )
        else {
            return []
        }

        var totals: [Date: Double] = [:]

        // Manual/grocery-confirm purchases (skip receipt-sourced entries —
        // those totals are already captured by the Receipt row below, and
        // double-counting would inflate spend for every receipt scan).
        for entry in priceEntries where entry.sourceReceiptLineItemID == nil {
            let ws = weekStart(for: entry.purchaseDate)
            guard ws >= earliestWeekStart, ws <= currentWeekStart else {
                continue
            }
            totals[ws, default: 0] += entry.totalPaidUSD
        }

        for receipt in receipts {
            // Only receipts the user confirmed count, and a flagged
            // duplicate the user hasn't dismissed would double a shop.
            guard receipt.userReviewed, isCountable(receipt, among: receipts) else {
                continue
            }
            let ws = weekStart(for: receipt.purchaseDate)
            guard ws >= earliestWeekStart, ws <= currentWeekStart else {
                continue
            }
            totals[ws, default: 0] += receipt.totalAmount
        }

        var result: [GroceryWeeklySpend] = []
        var cursor = earliestWeekStart
        while cursor <= currentWeekStart {
            result.append(GroceryWeeklySpend(
                weekStartDate: cursor,
                totalUSD: totals[cursor] ?? 0,
                budgetCapUSD: budgetCapUSD
            ))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return result
    }

    /// A receipt shares a `duplicateKey` with an earlier one (same store,
    /// date and total) when it was scanned twice. The user can dismiss the
    /// warning (`duplicateWarningDismissed`: "yes, two real shops"); otherwise
    /// only the first copy counts.
    private static func isCountable(_ receipt: Receipt, among receipts: [Receipt]) -> Bool {
        guard let key = receipt.duplicateKey, !key.isEmpty, !receipt.duplicateWarningDismissed else {
            return true
        }
        return !receipts.contains { other in
            other.id != receipt.id
                && other.duplicateKey == key
                && (other.createdAt < receipt.createdAt
                    || (other.createdAt == receipt.createdAt && other.id.uuidString < receipt.id.uuidString))
        }
    }
}
