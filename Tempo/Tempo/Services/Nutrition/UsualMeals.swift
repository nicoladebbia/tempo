//
// UsualMeals.swift
// Tempo
//
// "The usual" and "Same as yesterday" for the one capture screen. Both come
// from what the user really logged, never from a guess:
//
//   - usual     the meals eaten most often as this meal type, ranked by how
//               many different days they were eaten on, then by how close the
//               usual eating time is to now, then by how recent they are.
//               Needs at least two days (one meal is not a habit).
//   - yesterday yesterday's foods of the same meal type, as one meal.
//
// A meal is identified by the SET of its food names (order and case do not
// matter), not by its slot name, which is just "Lunch". The ranking is pure
// over `Entry` values so it is unit-testable without SwiftData; `load` is the
// thin reader over the canonical eaten history.
//

import Foundation
import SwiftData

enum UsualMeals {
    /// How far back the habit is read.
    static let windowDays = 28
    /// Different days a meal must show up on to count as "usual".
    static let minimumDays = 2

    /// One eaten meal, reduced to what the ranking needs.
    struct Entry: Equatable {
        let eatenAt: Date
        let type: MealType
        let foods: [PlannedFood]
    }

    /// A meal the user eats often, ready to log in one tap.
    struct Usual: Identifiable, Equatable {
        /// The normalised food-name set (stable across launches).
        let id: String
        let type: MealType
        /// The foods as eaten the last time.
        let foods: [PlannedFood]
        /// Different days it was eaten on in the window.
        let days: Int
        let lastEatenAt: Date

        var macros: MealMacros {
            foods.reduce(MealMacros.zero) {
                $0 + MealMacros(calories: $1.calories, protein: $1.proteinG, carbs: $1.carbsG, fat: $1.fatG)
            }
        }

        /// "Eggs, toast" / "Oats, banana and 2 more".
        var title: String {
            UsualMeals.title(of: foods)
        }
    }

    // MARK: - Ranking

    /// The meals eaten most often as `type`, best first. Today is ignored (it
    /// is what the user is logging now), as is anything older than the window.
    static func ranked(
        _ entries: [Entry],
        type: MealType,
        at time: Date = Date(),
        now: Date = Date(),
        limit: Int = 3,
        calendar: Calendar = .current
    ) -> [Usual] {
        guard limit > 0 else {
            return []
        }
        let todayStart = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: todayStart) else {
            return []
        }
        let candidates = entries.filter {
            $0.type == type && !$0.foods.isEmpty && $0.eatenAt >= windowStart && $0.eatenAt < todayStart
        }
        let groups = Dictionary(grouping: candidates) { signature(of: $0.foods) }
        let targetMinutes = minutesIntoDay(time, calendar: calendar)

        struct Scored {
            let usual: Usual
            let distance: Int
        }
        let scored: [Scored] = groups.compactMap { key, group in
            let days = Set(group.map { calendar.startOfDay(for: $0.eatenAt) }).count
            guard days >= minimumDays, let latest = group.max(by: { $0.eatenAt < $1.eatenAt }) else {
                return nil
            }
            let average = group.map { minutesIntoDay($0.eatenAt, calendar: calendar) }.reduce(0, +) / group.count
            return Scored(
                usual: Usual(id: key, type: type, foods: latest.foods, days: days, lastEatenAt: latest.eatenAt),
                distance: abs(average - targetMinutes)
            )
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.usual.days != rhs.usual.days {
                    return lhs.usual.days > rhs.usual.days
                }
                if lhs.distance != rhs.distance {
                    return lhs.distance < rhs.distance
                }
                if lhs.usual.lastEatenAt != rhs.usual.lastEatenAt {
                    return lhs.usual.lastEatenAt > rhs.usual.lastEatenAt
                }
                return lhs.usual.id < rhs.usual.id
            }
            .prefix(limit)
            .map(\.usual)
    }

    /// Yesterday's foods of `type`, in the order they were eaten, as one
    /// meal. nil when yesterday had none.
    static func yesterday(
        _ entries: [Entry],
        type: MealType,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Usual? {
        let todayStart = calendar.startOfDay(for: now)
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else {
            return nil
        }
        let meals = entries
            .filter { $0.type == type && !$0.foods.isEmpty && $0.eatenAt >= yesterdayStart && $0.eatenAt < todayStart }
            .sorted { $0.eatenAt < $1.eatenAt }
        guard let last = meals.last else {
            return nil
        }
        let foods = meals.flatMap(\.foods)
        return Usual(id: "yesterday-\(type.rawValue)", type: type, foods: foods, days: 1, lastEatenAt: last.eatenAt)
    }

    // MARK: - Helpers

    /// The food names, lowercased, trimmed, sorted and joined: the same
    /// foods in any order are the same meal.
    static func signature(of foods: [PlannedFood]) -> String {
        foods
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .sorted()
            .joined(separator: "|")
    }

    static func title(of foods: [PlannedFood]) -> String {
        let names = foods.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !names.isEmpty else {
            return "Meal"
        }
        // Sentence case: "Oats, banana", not "oats, banana".
        let title = names.count <= 2
            ? names.joined(separator: ", ")
            : "\(names[0]), \(names[1]) and \(names.count - 2) more"
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    private static func minutesIntoDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - Reading the history

    /// The eaten meals of the habit window, as ranking entries. Supplement
    /// doses and meals without foods are not meals.
    @MainActor
    static func entries(
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Entry] {
        let todayStart = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: todayStart) else {
            return []
        }
        return entries(from: EatenMealHistory.fetch(from: start, to: todayStart, in: context, now: now))
    }

    @MainActor
    static func entries(from meals: [PlannedMeal]) -> [Entry] {
        meals.compactMap { meal in
            guard meal.status == .eaten, !EatenMealRecorder.isSupplementDose(meal) else {
                return nil
            }
            let foods = meal.foods
            guard !foods.isEmpty else {
                return nil
            }
            let eatenAt = meal.actualEatenAt ?? meal.dayDate
            let type = MealType.inferred(fromName: meal.mealName) ?? EatenMealRecorder.defaultMealType(for: eatenAt)
            return Entry(eatenAt: eatenAt, type: type, foods: foods)
        }
    }
}
