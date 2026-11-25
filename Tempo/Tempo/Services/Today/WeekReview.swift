//
// WeekReview.swift
// Tempo
//
// "Week in review": one page that says how the week went in four areas,
// training, food, recovery and daily tasks with study, with the real numbers
// next to the week before and one plain sentence for each.
//
// Pure: per-day rows in, totals and sentences out. `WeekReviewLoader` reads
// the rows from SwiftData.
//

import Foundation
import SwiftData

// MARK: - WeekReviewDay

/// One calendar day's numbers. A field is nil or zero when nothing was recorded.
struct WeekReviewDay: Equatable {
    var date: Date
    var sessions = 0
    var trainingMinutes = 0
    var volumeKg = 0.0
    var mealsEaten = 0
    var kcal = 0
    var protein = 0
    var recoveryScore: Int?
    var sleepHours: Double?
    var tasksDone = 0
    var tasksTotal = 0
    var studyMinutes = 0
}

// MARK: - WeekTotals

struct WeekTotals: Equatable {
    var sessions = 0
    var trainingMinutes = 0
    var volumeKg = 0.0

    /// Days with at least one meal eaten.
    var foodDays = 0
    var avgKcal: Int?
    var avgProtein: Int?

    var recoveryDays = 0
    var avgRecovery: Int?
    var avgSleepHours: Double?

    var tasksDone = 0
    var tasksTotal = 0
    var studyMinutes = 0

    /// Days where every task was done.
    var perfectDays = 0

    var completionRate: Double? {
        tasksTotal > 0 ? Double(tasksDone) / Double(tasksTotal) : nil
    }

    /// Nothing recorded in any area.
    var isEmpty: Bool {
        sessions == 0 && foodDays == 0 && recoveryDays == 0 && tasksTotal == 0 && studyMinutes == 0
    }
}

// MARK: - WeekReview

struct WeekReview: Equatable {
    let weekStart: Date
    let thisWeek: WeekTotals
    let lastWeek: WeekTotals

    var training: String {
        WeekReviewWords.training(thisWeek, lastWeek)
    }

    var food: String {
        WeekReviewWords.food(thisWeek, lastWeek)
    }

    var recovery: String {
        WeekReviewWords.recovery(thisWeek, lastWeek)
    }

    var discipline: String {
        WeekReviewWords.discipline(thisWeek, lastWeek)
    }

    /// One short line for the card on Today: the numbers worth a glance.
    var headline: String {
        var parts: [String] = []
        if thisWeek.sessions > 0 {
            parts.append(WeekReviewWords.count(thisWeek.sessions, "session"))
        }
        if thisWeek.perfectDays > 0 {
            parts.append(WeekReviewWords.count(thisWeek.perfectDays, "day") + " with every task done")
        }
        if let recovery = thisWeek.avgRecovery {
            parts.append("recovery \(recovery)%")
        }
        guard let first = parts.first else {
            return "A look at how the week went."
        }
        let line = ([first.prefix(1).uppercased() + first.dropFirst()] + parts.dropFirst()).joined(separator: ", ")
        return line + "."
    }
}

// MARK: - WeekReviewBuilder

enum WeekReviewBuilder {
    /// Monday of the week that holds `date`.
    static func monday(of date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        return calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: day) ?? day
    }

    /// The day the review is about. Monday morning the new week is still
    /// empty, so the review is of the week that just ended (Sunday).
    static func reference(for now: Date, calendar: Calendar = .current) -> Date {
        let isMonday = calendar.component(.weekday, from: now) == 2
        guard isMonday, calendar.component(.hour, from: now) < TodayPromptPlanner.mondayMorningEnd else {
            return now
        }
        return calendar.date(byAdding: .day, value: -1, to: now) ?? now
    }

    /// The review for the week holding `now`, against the seven days before it.
    static func build(days: [WeekReviewDay], now: Date, calendar: Calendar = .current) -> WeekReview {
        let start = monday(of: now, calendar: calendar)
        let lastStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return WeekReview(
            weekStart: start,
            thisWeek: totals(days.filter { $0.date >= start && $0.date < end }),
            lastWeek: totals(days.filter { $0.date >= lastStart && $0.date < start })
        )
    }

    static func totals(_ days: [WeekReviewDay]) -> WeekTotals {
        var totals = WeekTotals()
        totals.sessions = days.reduce(0) { $0 + $1.sessions }
        totals.trainingMinutes = days.reduce(0) { $0 + $1.trainingMinutes }
        totals.volumeKg = days.reduce(0) { $0 + $1.volumeKg }

        let eaten = days.filter { $0.mealsEaten > 0 }
        totals.foodDays = eaten.count
        if !eaten.isEmpty {
            totals.avgKcal = eaten.reduce(0) { $0 + $1.kcal } / eaten.count
            totals.avgProtein = eaten.reduce(0) { $0 + $1.protein } / eaten.count
        }

        let scores = days.compactMap(\.recoveryScore)
        totals.recoveryDays = scores.count
        if !scores.isEmpty {
            totals.avgRecovery = Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        }
        let sleeps = days.compactMap(\.sleepHours).filter { $0 > 0 }
        if !sleeps.isEmpty {
            totals.avgSleepHours = sleeps.reduce(0, +) / Double(sleeps.count)
        }

        totals.tasksDone = days.reduce(0) { $0 + $1.tasksDone }
        totals.tasksTotal = days.reduce(0) { $0 + $1.tasksTotal }
        totals.studyMinutes = days.reduce(0) { $0 + $1.studyMinutes }
        totals.perfectDays = days.count { $0.tasksTotal > 0 && $0.tasksDone == $0.tasksTotal }
        return totals
    }
}

// MARK: - WeekReviewWords

/// One sentence per area. Each says the number first, then how it compares.
enum WeekReviewWords {
    static func training(_ week: WeekTotals, _ last: WeekTotals) -> String {
        guard week.sessions > 0 else {
            return last.sessions > 0
                ? "No session logged yet. Last week you did \(count(last.sessions, "session"))."
                : "No session logged this week."
        }
        let base = "\(count(week.sessions, "session")), \(duration(minutes: week.trainingMinutes)) in the gym"
        guard last.sessions > 0 else {
            return base + "."
        }
        return base + ", " + comparison(week.sessions - last.sessions, unit: "session") + "."
    }

    static func food(_ week: WeekTotals, _ last: WeekTotals) -> String {
        guard let kcal = week.avgKcal, let protein = week.avgProtein else {
            return "No meals logged this week."
        }
        var line = "Logged \(count(week.foodDays, "day")), averaging \(kcal.formatted())\u{00A0}kcal and \(protein)\u{00A0}g protein."
        if let lastProtein = last.avgProtein, lastProtein != protein {
            let move = protein - lastProtein
            line += " Protein \(move > 0 ? "up" : "down") \(abs(move))\u{00A0}g on last week."
        }
        return line
    }

    static func recovery(_ week: WeekTotals, _ last: WeekTotals) -> String {
        guard let score = week.avgRecovery else {
            return "No recovery readings this week."
        }
        var line = "Recovery averaged \(score)%"
        if let lastScore = last.avgRecovery, lastScore != score {
            let move = score - lastScore
            line += ", \(move > 0 ? "up" : "down") \(abs(move)) \(abs(move) == 1 ? "point" : "points")"
        }
        line += "."
        if let sleep = week.avgSleepHours {
            line += " You slept \(duration(minutes: Int((sleep * 60).rounded()))) a night."
        }
        return line
    }

    static func discipline(_ week: WeekTotals, _ last: WeekTotals) -> String {
        var parts: [String] = []
        if week.tasksTotal > 0 {
            let rate = Int(((week.completionRate ?? 0) * 100).rounded())
            var tasks = "\(week.tasksDone) of \(week.tasksTotal) tasks done (\(rate)%)"
            if let lastRate = last.completionRate {
                let move = rate - Int((lastRate * 100).rounded())
                if move != 0 {
                    tasks += ", \(move > 0 ? "up" : "down") \(abs(move)) points"
                }
            }
            parts.append(tasks)
        }
        if week.studyMinutes > 0 {
            var study = "\(duration(minutes: week.studyMinutes)) of study"
            if last.studyMinutes > 0, last.studyMinutes != week.studyMinutes {
                let move = week.studyMinutes - last.studyMinutes
                study += " (\(move > 0 ? "+" : "-")\(duration(minutes: abs(move))))"
            }
            parts.append(study)
        }
        guard !parts.isEmpty else {
            return "No tasks or study logged this week."
        }
        return parts.joined(separator: ", ") + "."
    }

    // MARK: Pieces

    static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    /// 135 -> "2h 15m", 300 -> "5h", 45 -> "45m".
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(rest)m"
        }
    }

    /// "1 session more than last week", "2 sessions fewer than last week", "the same as last week".
    static func comparison(_ delta: Int, unit: String) -> String {
        switch delta {
        case 0: "the same as last week"
        case 1...: "\(count(delta, unit)) more than last week"
        default: "\(count(-delta, unit)) fewer than last week"
        }
    }
}

// MARK: - WeekReviewLoader

@MainActor
enum WeekReviewLoader {
    /// Fourteen days of rows ending with the week that holds `now`.
    static func days(now: Date, calendar: Calendar = .current, in context: ModelContext) -> [WeekReviewDay] {
        let thisMonday = WeekReviewBuilder.monday(of: now, calendar: calendar)
        guard let from = calendar.date(byAdding: .day, value: -7, to: thisMonday),
              let to = calendar.date(byAdding: .day, value: 7, to: thisMonday)
        else {
            return []
        }

        let plans = (try? context.fetch(FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { $0.date >= from && $0.date < to }
        ))) ?? []
        let recoveries = (try? context.fetch(FetchDescriptor<DailyRecovery>(
            predicate: #Predicate<DailyRecovery> { $0.date >= from && $0.date < to }
        ))) ?? []
        let accountabilities = (try? context.fetch(FetchDescriptor<DailyAccountability>(
            predicate: #Predicate<DailyAccountability> { $0.date >= from && $0.date < to }
        ))) ?? []

        return (0 ..< 14).compactMap { offset -> WeekReviewDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: from) else {
                return nil
            }
            var row = WeekReviewDay(date: day)

            let done = plans.filter {
                calendar.isDate($0.date, inSameDayAs: day) && $0.status == .completed
            }
            row.sessions = done.count
            row.trainingMinutes = done.reduce(0) { $0 + ($1.actualDurationMinutes ?? 0) }
            row.volumeKg = done.reduce(0) { $0 + $1.totalVolume }

            // The same canonical eaten total every Fuel screen shows.
            let meals = CanonicalMeals.meals(on: day, in: context)
            let eaten = meals.filter {
                ($0.status == .eaten || $0.status == .modified) && !EatenMealRecorder.isSupplementDose($0)
            }
            row.mealsEaten = eaten.count
            let totals = CanonicalMeals.eatenRoundedTotals(of: meals)
            row.kcal = totals.calories
            row.protein = totals.protein

            if let recovery = recoveries.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                row.recoveryScore = Int(recovery.recoveryScore.rounded())
                row.sleepHours = recovery.sleepHours
            }
            if let accountability = accountabilities.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                row.tasksDone = accountability.completedCount
                row.tasksTotal = accountability.totalCount
                row.studyMinutes = accountability.totalStudyMinutes
            }
            return row
        }
    }

    static func review(now: Date, calendar: Calendar = .current, in context: ModelContext) -> WeekReview {
        WeekReviewBuilder.build(days: days(now: now, calendar: calendar, in: context), now: now, calendar: calendar)
    }
}
