//
// NextUpSummary.swift
// Tempo
//
// The answer to Siri's "What's next": the next session, the next meal and the
// next task, read from the same saved state the Today screen is built from
// (today's workout plan, the active meal plan, today's tasks). It reads the
// store directly, not a copy saved earlier, so the answer is current even
// when the app has no screen. The wording is a pure function of the facts so
// it can be tested without a store.
//

import Foundation
import SwiftData

// MARK: - NextUpSummary

struct NextUpSummary: Equatable, Sendable {
    struct Session: Equatable, Sendable {
        var name: String
        var inProgress: Bool
    }

    struct Meal: Equatable, Sendable {
        var name: String
        /// "HH:mm"
        var time: String
    }

    var session: Session?
    var meal: Meal?
    var tasksLeft: Int
    var tasksTotal: Int
    var firstTask: String?

    /// Nothing on the plan at all (a day with no session, no meal and no tasks set up).
    var isEmpty: Bool {
        session == nil && meal == nil && tasksTotal == 0
    }

    // MARK: Wording

    /// One short paragraph, spoken and shown by Siri.
    var spoken: String {
        if isEmpty {
            return "Nothing is planned yet today. Open Tempo to set up your day."
        }
        var sentences: [String] = []
        if let session {
            sentences.append(session.inProgress
                ? "\(session.name) is in progress."
                : "Next session: \(session.name).")
        }
        if let meal {
            sentences.append("Next meal: \(meal.name) at \(meal.time).")
        }
        if tasksLeft > 0 {
            let count = tasksLeft == 1 ? "1 task left" : "\(tasksLeft) tasks left"
            sentences.append(firstTask.map { "\(count), starting with \($0)." } ?? "\(count).")
        } else if tasksTotal > 0 {
            sentences.append("All your tasks are done.")
        }
        if session == nil, meal == nil, tasksLeft == 0 {
            sentences.append("Nothing else is due.")
        }
        return sentences.joined(separator: " ")
    }
}

// MARK: - NextUpReader

@MainActor
enum NextUpReader {
    static func read(in context: ModelContext, now: Date = Date(), calendar: Calendar = .current) -> NextUpSummary {
        let (left, total, first) = tasks(in: context, now: now, calendar: calendar)
        return NextUpSummary(
            session: session(in: context, now: now),
            meal: meal(in: context, now: now, calendar: calendar),
            tasksLeft: left,
            tasksTotal: total,
            firstTask: first
        )
    }

    /// Today's session when there is still one to do (or one under way).
    private static func session(in context: ModelContext, now: Date) -> NextUpSummary.Session? {
        guard let plan = DashboardViewModel.todayWorkoutPlan(in: context, now: now) else {
            return nil
        }
        switch DashboardViewModel.dashboardWorkoutStatus(for: plan) {
        case .planned:
            return .init(name: plan.type.displayName, inProgress: plan.status == .inProgress)
        case .completed,
             .restDay,
             .none:
            return nil
        }
    }

    /// The next planned meal of the active plan, the same pick as the Today hero.
    private static func meal(in context: ModelContext, now: Date, calendar: Calendar) -> NextUpSummary.Meal? {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { $0.dayDate >= start && $0.dayDate < end },
            sortBy: [SortDescriptor(\.mealNumber)]
        )
        let meals = ((try? context.fetch(descriptor)) ?? []).filter {
            $0.mealPlan?.isActive == true || $0.mealPlan == nil
        }
        return MealScheduleHelpers.nextUpcomingMeal(in: meals, now: now, calendar: calendar).map {
            .init(name: $0.mealName, time: $0.scheduledTime)
        }
    }

    /// Tasks left today, how many there are, and the first one left by name
    /// (the order Today lists them in).
    private static func tasks(
        in context: ModelContext, now: Date, calendar: Calendar
    ) -> (left: Int, total: Int, first: String?) {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return (0, 0, nil)
        }
        let descriptor = FetchDescriptor<DailyAccountability>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        var items: [(title: String, done: Bool)]
        if let today = (try? context.fetch(descriptor))?.first {
            items = (today.nonNegotiableProgress ?? []).compactMap { progress in
                progress.nonNegotiable.map { ($0.name, progress.isCompleted) }
            }
        } else {
            // No day record yet: the active tasks, none done (as Today shows them).
            let active = FetchDescriptor<NonNegotiable>(predicate: #Predicate { $0.isActive })
            items = ((try? context.fetch(active)) ?? []).map { ($0.name, false) }
        }
        items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let open = items.filter { !$0.done }
        return (open.count, items.count, open.first?.title)
    }
}
