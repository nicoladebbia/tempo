//
// WidgetSnapshot+Today.swift
// Tempo
//
// Builds the widget snapshot from the `TodaySnapshot` the Today screen draws,
// so every number a widget shows is the number Today shows, and the "next up"
// line is the same `TodayNextAction` choice as the Today hero.
//

import Foundation

extension WidgetSnapshot {
    init(today: TodaySnapshot, now: Date = Date(), calendar: Calendar = .current) {
        let fuel = today.fuel
        self.init(
            day: today.day,
            writtenAt: now,
            score: today.score,
            tasksDone: today.tasksDone,
            tasksTotal: today.tasks.count,
            calories: fuel.calories,
            calorieTarget: fuel.calorieTarget,
            protein: fuel.protein,
            proteinTarget: fuel.proteinTarget,
            carbs: fuel.carbs,
            carbsTarget: fuel.carbsTarget,
            fat: fuel.fat,
            fatTarget: fuel.fatTarget,
            waterMl: fuel.waterMl,
            waterTargetMl: fuel.waterTargetMl > 0 ? fuel.waterTargetMl : nil,
            next: TodayNextAction
                .choose(for: today, hour: calendar.component(.hour, from: now))
                .widgetNext(for: today)
        )
    }

    /// Equal apart from the moment it was written: a refresh that changed
    /// nothing does not rewrite the file or reload the widgets.
    func sameContent(as other: WidgetSnapshot) -> Bool {
        var a = self
        a.writtenAt = other.writtenAt
        return a == other
    }
}

// MARK: - TodayNextAction

extension TodayNextAction {
    /// The widget's copy of the Today hero: the same choice and the same titles.
    /// Two detail lines (first meal, all done) drop their first sentence to fit
    /// a small widget; the rest are word for word. Keep both in step.
    func widgetNext(for snapshot: TodaySnapshot) -> WidgetSnapshot.Next {
        switch self {
        case let .workout(name, resume):
            WidgetSnapshot.Next(
                kind: .workout,
                title: name,
                detail: resume ? String(localized: "You started this session. Pick it up where you left off.") : String(localized: "Today's session is ready."),
                trailing: snapshot.workout.durationMinutes.map { String(localized: "\($0) min") },
                destination: .train
            )
        case let .meal(meal):
            WidgetSnapshot.Next(
                kind: .meal,
                title: meal.name,
                detail: String(localized: "\(meal.calories.formatted()) kcal · \(meal.protein) g protein"),
                trailing: meal.time,
                destination: .fuel
            )
        case .rest:
            WidgetSnapshot.Next(
                kind: .rest, title: String(localized: "Rest day"),
                detail: String(localized: "No session today. Recovery sets up tomorrow."), trailing: nil, destination: .today
            )
        case .firstMeal:
            WidgetSnapshot.Next(
                kind: .firstMeal, title: String(localized: "Log today's first meal"),
                detail: String(localized: "One meal starts your score and your targets."), trailing: nil, destination: .fuel
            )
        case let .focus(left):
            WidgetSnapshot.Next(
                kind: .focus, title: String(localized: "Study block"),
                detail: String(localized: "\(left) min left to reach today's study target."), trailing: nil, destination: .today
            )
        case let .tasks(left):
            WidgetSnapshot.Next(
                kind: .tasks, title: left == 1 ? String(localized: "1 task left") : String(localized: "\(left) tasks left"),
                detail: String(localized: "Finish them to unlock the day."), trailing: nil, destination: .today
            )
        case .setUpTasks:
            WidgetSnapshot.Next(
                kind: .setUpTasks, title: String(localized: "Set your daily tasks"),
                detail: String(localized: "Pick the few things you do every day, no matter what."), trailing: nil, destination: .today
            )
        case .allDone:
            WidgetSnapshot.Next(
                kind: .allDone, title: String(localized: "Day complete"),
                detail: String(localized: "Session, tasks and study are all done."), trailing: nil, destination: .today
            )
        }
    }
}
