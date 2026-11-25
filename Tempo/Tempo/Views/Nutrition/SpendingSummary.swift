//
// SpendingSummary.swift
// Tempo
//
// The numbers on the Spending page, as plain data: eight weeks of grocery
// spend (confirmed receipts plus purchases typed in by hand, checked against
// the weekly budget) and what they add up to. Built from the same
// `GroceryWeeklySpendCalculator` the old Spend History used, so a week shows
// the same total as before.
//

import Foundation

struct SpendingSummary: Equatable {
    /// Oldest first; the last one is the current week.
    let weeks: [GroceryWeeklySpend]

    static let weekCount = 8

    static func make(
        receipts: [Receipt],
        priceEntries: [PantryPriceEntry],
        budgetCapUSD: Int?,
        now: Date = Date()
    ) -> SpendingSummary {
        SpendingSummary(weeks: GroceryWeeklySpendCalculator.compute(
            priceEntries: priceEntries,
            receipts: receipts,
            weeks: weekCount,
            budgetCapUSD: budgetCapUSD,
            now: now
        ))
    }

    /// This week.
    var current: GroceryWeeklySpend? {
        weeks.last
    }

    /// The week with this id (its Monday), or this week when there is none.
    func week(_ id: Date?) -> GroceryWeeklySpend? {
        weeks.first { $0.id == id } ?? current
    }

    /// True when at least one week has spend in it.
    var hasSpend: Bool {
        weeks.contains { $0.totalUSD > 0 }
    }

    /// Everything spent over the eight weeks.
    var total: Double {
        weeks.reduce(0) { $0 + $1.totalUSD }
    }

    /// The weekly average since the first week with spend, so a new user's
    /// empty early weeks do not drag it down. Nil with no spend at all.
    var averagePerWeek: Double? {
        guard let first = weeks.firstIndex(where: { $0.totalUSD > 0 }) else {
            return nil
        }
        let counted = weeks[first...]
        return counted.reduce(0) { $0 + $1.totalUSD } / Double(counted.count)
    }

    /// How many weeks went over the budget.
    var overBudgetWeeks: Int {
        weeks.filter(\.isOverBudget).count
    }

    // MARK: Words

    /// "$73.45".
    static func money(_ amount: Double) -> String {
        "$" + amount.tempoDecimal(2)
    }

    /// Where a week stands against its budget, in a line.
    static func budgetLine(_ week: GroceryWeeklySpend) -> String {
        guard let cap = week.budgetCapUSD else {
            return String(localized: "No weekly budget set")
        }
        let gap = money(abs(Double(cap) - week.totalUSD))
        return week.isOverBudget ? String(localized: "\(gap) over your $\(cap) budget") : String(localized: "\(gap) left of your $\(cap) budget")
    }

    /// "Average $84.20 a week · 1 week over budget", or nil with no spend yet.
    var footer: String? {
        guard let average = averagePerWeek else {
            return nil
        }
        var line = String(localized: "Average \(Self.money(average)) a week")
        if overBudgetWeeks > 0 {
            line += " · " + String(localized: "\(FuelWords.count(overBudgetWeeks, "week")) over budget")
        }
        return line
    }
}
