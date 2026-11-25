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
// The first sentence is the one Today's Next card shows: both ask
// `NextStepEngine`, so Siri and the card can never name different things. The
// other facts follow it, minus the one it already said.
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
    /// What Today's Next card would say right now. Leads the answer when there is one.
    var next: NextStep?

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
        // The lead already says one of the three facts: do not say it twice.
        var saysSession = false, saysMeal = false, saysTasks = false
        if let next {
            sentences.append(next.line)
            switch next.action {
            case .workout: saysSession = true
            case .meal: saysMeal = true
            case .tasks: saysTasks = true
            case .rest,
                 .firstMeal,
                 .focus,
                 .setUpTasks,
                 .allDone: break
            }
        }
        if let session, !saysSession {
            sentences.append(session.inProgress
                ? "\(session.name) is in progress."
                : "Next session: \(session.name).")
        }
        if let meal, !saysMeal {
            sentences.append("Next meal: \(meal.name) at \(meal.time).")
        }
        if tasksLeft > 0 {
            if saysTasks {
                // "Next: 3 tasks left." already gave the count; name where to start.
                if let firstTask {
                    sentences.append("Start with \(firstTask).")
                }
            } else {
                let count = tasksLeft == 1 ? "1 task left" : "\(tasksLeft) tasks left"
                sentences.append(firstTask.map { "\(count), starting with \($0)." } ?? "\(count).")
            }
        } else if tasksTotal > 0 {
            sentences.append("All your tasks are done.")
        }
        if next == nil, session == nil, meal == nil, tasksLeft == 0 {
            sentences.append("Nothing else is due.")
        }
        return sentences.joined(separator: " ")
    }
}

// MARK: - NextUpReader

@MainActor
enum NextUpReader {
    static func read(
        in context: ModelContext, now: Date = Date(), calendar: Calendar = .current,
        cache: any TodayCaching = TodayCache.shared
    ) -> NextUpSummary {
        let (left, total, first) = tasks(in: context, now: now, calendar: calendar)
        let plan = DashboardViewModel.todayWorkoutPlan(in: context, now: now)
        let upcoming = nextMeal(in: context, now: now, calendar: calendar)
        var summary = NextUpSummary(
            session: session(for: plan),
            meal: upcoming.map { .init(name: $0.mealName, time: $0.scheduledTime) },
            tasksLeft: left,
            tasksTotal: total,
            firstTask: first
        )
        // Without Today's saved copy (recovery source, calories, study) the engine would guess
        // "log your first meal" for someone who has eaten: then Siri lists the facts as before.
        if !summary.isEmpty, let saved = cache.load(now: now, calendar: calendar) {
            summary.next = nextStep(
                saved: saved, plan: plan, meal: upcoming, now: now, calendar: calendar,
                tasks: total > 0 ? openAndDone(in: context, now: now, calendar: calendar) : nil
            )
        }
        return summary
    }

    /// The step Today's card would show, from the saved copy of Today (recovery source,
    /// calories, study) with what the store says now put over it (the session, the next
    /// meal, the tasks), run through the same `NextStepEngine`.
    static func nextStep(
        saved: TodaySnapshot, plan: WorkoutPlan?, meal: PlannedMeal?, now: Date, calendar: Calendar,
        tasks: [TodaySnapshot.TaskItem]?
    ) -> NextStep? {
        var snapshot = saved
        if let plan {
            snapshot.workout = .init(
                status: TodaySnapshot.workoutStatus(DashboardViewModel.dashboardWorkoutStatus(for: plan)),
                name: plan.type.displayName, inProgress: plan.status == .inProgress, durationMinutes: nil
            )
        }
        snapshot.nextMeal = meal.map {
            .init(
                id: $0.id, name: $0.mealName, time: $0.scheduledTime, calories: Int($0.totalCalories.rounded()),
                protein: Int($0.totalProtein.rounded()), imminent: MealScheduleHelpers.isImminent(meal: $0, now: now)
            )
        }
        if let tasks {
            snapshot.tasks = tasks
        }
        return NextStepEngine.next(for: snapshot, hour: calendar.component(.hour, from: now))
    }

    /// Today's session when there is still one to do (or one under way).
    private static func session(for plan: WorkoutPlan?) -> NextUpSummary.Session? {
        guard let plan else {
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
    private static func nextMeal(in context: ModelContext, now: Date, calendar: Calendar) -> PlannedMeal? {
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
        return MealScheduleHelpers.nextUpcomingMeal(in: meals, now: now, calendar: calendar)
    }

    /// Today's tasks in the order Today lists them, with whether each is done.
    private static func openAndDone(in context: ModelContext, now: Date, calendar: Calendar) -> [TodaySnapshot.TaskItem] {
        taskRows(in: context, now: now, calendar: calendar).map {
            TodaySnapshot.TaskItem(id: $0.id, title: $0.title, done: $0.done)
        }
    }

    /// Tasks left today, how many there are, and the first one left by name
    /// (the order Today lists them in).
    private static func tasks(
        in context: ModelContext, now: Date, calendar: Calendar
    ) -> (left: Int, total: Int, first: String?) {
        let rows = taskRows(in: context, now: now, calendar: calendar)
        let open = rows.filter { !$0.done }
        return (open.count, rows.count, open.first?.title)
    }

    private static func taskRows(
        in context: ModelContext, now: Date, calendar: Calendar
    ) -> [(id: UUID, title: String, done: Bool)] {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return []
        }
        let descriptor = FetchDescriptor<DailyAccountability>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        var items: [(id: UUID, title: String, done: Bool)]
        if let today = (try? context.fetch(descriptor))?.first {
            items = (today.nonNegotiableProgress ?? []).compactMap { progress in
                progress.nonNegotiable.map { ($0.id, $0.name, progress.isCompleted) }
            }
        } else {
            // No day record yet: the active tasks, none done (as Today shows them).
            let active = FetchDescriptor<NonNegotiable>(predicate: #Predicate { $0.isActive })
            items = ((try? context.fetch(active)) ?? []).map { ($0.id, $0.name, false) }
        }
        items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return items
    }
}
