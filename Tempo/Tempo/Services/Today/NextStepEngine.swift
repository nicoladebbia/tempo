//
// NextStepEngine.swift
// Tempo
//
// The one place that decides "what do I do next". Today's Next card and the
// `NextStepBar` that closes a workout, a meal log, a focus session, Recovery
// and Lockdown all ask this engine, so they can never name different things.
//
// It is pure: a snapshot of the day, the hour and where the person is go in,
// one `NextStep` (or nothing) comes out. After something has just been done
// the engine does not suggest the same thing again.
//

import Foundation

// MARK: - NextStepPlace

/// Where the next-step line is being shown.
enum NextStepPlace: String, CaseIterable {
    case today
    case workoutSummary
    case afterMeal
    case afterFocus
    case recoveryEnd
    case lockdownDone

    /// What was just done here, so it is never offered again straight away.
    fileprivate var justDone: NextStepEngine.Kind? {
        switch self {
        case .today: nil
        case .workoutSummary: .workout
        case .afterMeal: .meal
        case .afterFocus: .focus
        case .recoveryEnd: .rest
        case .lockdownDone: .tasks
        }
    }
}

// MARK: - NextStep

/// One suggestion, with every word it needs.
struct NextStep: Equatable {
    let action: TodayNextAction
    /// Card heading ("Push", "Rest day").
    let title: String
    /// Card body, one sentence.
    let detail: String
    /// The single button; nil when there is nothing to press (day complete).
    let buttonTitle: String?
    let buttonIcon: String?
    /// The whole suggestion as one line, for the bar ("Next: Lunch at 12:30").
    let line: String
}

// MARK: - NextStepEngine

enum NextStepEngine {
    /// The kinds of thing the engine can suggest.
    enum Kind: Hashable {
        case workout
        case meal
        case rest
        case focus
        case tasks
    }

    /// After this hour an unfinished session gives way to the next meal.
    static let lateHour = 21

    /// The next step, or nil when there is nothing worth saying. On Today the
    /// answer is never nil (a finished day still says so); in the other places
    /// a finished day says nothing.
    static func next(for snapshot: TodaySnapshot, hour: Int, place: NextStepPlace = .today) -> NextStep? {
        let adjusted = settled(snapshot, for: place)
        let skipping = place.justDone.map { Set([$0]) } ?? []
        let action = choose(for: adjusted, hour: hour, skipping: skipping)
        if place != .today, action == .allDone {
            return nil
        }
        return step(for: action, snapshot: adjusted)
    }

    /// The snapshot as it is the moment after what just happened. The saved
    /// copy lags by a refresh, so the engine corrects the one fact it knows.
    private static func settled(_ snapshot: TodaySnapshot, for place: NextStepPlace) -> TodaySnapshot {
        var copy = snapshot
        switch place {
        case .today,
             .recoveryEnd:
            break
        case .workoutSummary:
            copy.workout.status = .completed
            copy.workout.inProgress = false
        case .afterMeal:
            copy.fuel.calories = max(copy.fuel.calories ?? 0, 1)
        case .afterFocus:
            copy.study.minutes = max(copy.study.minutes, copy.study.targetMinutes)
        case .lockdownDone:
            copy.tasks = copy.tasks.map { TodaySnapshot.TaskItem(id: $0.id, title: $0.title, done: true) }
        }
        return copy
    }

    // MARK: Choosing

    /// The single thing to do now. Rules run in order and the first that
    /// applies wins; `skipping` removes the kinds that were just done.
    static func choose(for snapshot: TodaySnapshot, hour: Int, skipping: Set<Kind> = []) -> TodayNextAction {
        let workout = snapshot.workout
        if !skipping.contains(.workout), workout.status == .planned {
            // A session already started always wins; otherwise late in the
            // day the next meal is the more useful thing to show.
            if workout.inProgress || hour < lateHour || snapshot.nextMeal == nil || skipping.contains(.meal) {
                return .workout(name: workout.name ?? String(localized: "Workout"), resume: workout.inProgress)
            }
        }
        if !skipping.contains(.meal) {
            if let meal = snapshot.nextMeal, meal.imminent || workout.status != .rest {
                return .meal(meal)
            }
            // "Open recovery" needs a recovery reading to open. With no tracker
            // and nothing eaten yet (day one), logging a meal is the useful start.
            if !snapshot.recovery.hasSource, workout.status == .rest || workout.status == .none,
               (snapshot.fuel.calories ?? 0) == 0
            {
                return .firstMeal
            }
        }
        if !skipping.contains(.rest), workout.status == .rest, snapshot.recovery.hasSource {
            return .rest
        }
        if !skipping.contains(.focus), snapshot.studyLeft > 0 {
            return .focus(minutesLeft: snapshot.studyLeft)
        }
        if !skipping.contains(.tasks) {
            if snapshot.tasksLeft > 0 {
                return .tasks(left: snapshot.tasksLeft)
            }
            if snapshot.tasks.isEmpty {
                return .setUpTasks
            }
        }
        return .allDone
    }

    // MARK: Words

    static func step(for action: TodayNextAction, snapshot: TodaySnapshot) -> NextStep {
        NextStep(
            action: action,
            title: title(for: action),
            detail: detail(for: action),
            buttonTitle: button(for: action)?.title,
            buttonIcon: button(for: action)?.icon,
            line: line(for: action)
        )
    }

    static func title(for action: TodayNextAction) -> String {
        switch action {
        case let .workout(name, _): name
        case let .meal(meal): meal.name
        case .rest: String(localized: "Rest day")
        case .firstMeal: String(localized: "Log today's first meal")
        case .focus: String(localized: "Study block")
        case let .tasks(left): left == 1 ? String(localized: "1 task left") : String(localized: "\(left) tasks left")
        case .setUpTasks: String(localized: "Set your daily tasks")
        case .allDone: String(localized: "Day complete")
        }
    }

    static func detail(for action: TodayNextAction) -> String {
        switch action {
        case let .workout(_, resume):
            resume ? String(localized: "You started this session. Pick it up where you left off.") : String(localized: "Today's session is ready.")
        case let .meal(meal):
            String(localized: "\(meal.calories.formatted()) kcal · \(meal.protein) g protein")
        case .rest:
            String(localized: "No session today. Recovery sets up tomorrow.")
        case .firstMeal:
            String(localized: "Nothing logged yet today. One meal starts your score and your targets.")
        case let .focus(left):
            String(localized: "\(left) min left to reach today's study target.")
        case .tasks:
            String(localized: "Finish them to unlock the day.")
        case .setUpTasks:
            String(localized: "Pick the few things you do every day, no matter what.")
        case .allDone:
            String(localized: "Session, tasks and study are all done. Nothing else is due.")
        }
    }

    static func button(for action: TodayNextAction) -> (title: String, icon: String)? {
        switch action {
        case let .workout(_, resume): (resume ? String(localized: "Resume session") : String(localized: "Start session"), "play.fill")
        case .meal: (String(localized: "Open meal"), "fork.knife")
        case .rest: (String(localized: "Open recovery"), "heart.fill")
        case .firstMeal: (String(localized: "Log a meal"), "fork.knife")
        case .focus: (String(localized: "Start focus timer"), "timer")
        case .tasks: (String(localized: "Open tasks"), "checklist")
        case .setUpTasks: (String(localized: "Choose tasks"), "plus")
        case .allDone: nil
        }
    }

    /// One short line, for places with room for a sentence and a button.
    static func line(for action: TodayNextAction) -> String {
        switch action {
        case let .workout(name, resume): resume ? String(localized: "Pick up \(name).") : String(localized: "Next: \(name) session.")
        case let .meal(meal): String(localized: "Next: \(meal.name) at \(meal.time).")
        case .rest: String(localized: "Next: a rest day. Check your recovery.")
        case .firstMeal: String(localized: "Next: log your first meal.")
        case let .focus(left): String(localized: "Next: \(left) min of study.")
        case let .tasks(left): left == 1 ? String(localized: "Next: 1 task left.") : String(localized: "Next: \(left) tasks left.")
        case .setUpTasks: String(localized: "Next: choose your daily tasks.")
        case .allDone: String(localized: "Day complete.")
        }
    }
}

// MARK: - TodayNextAction

extension TodayNextAction {
    /// After this hour an unfinished session gives way to the next meal.
    static let lateHour = NextStepEngine.lateHour

    /// Kept for the callers that only want the action; the rules live in `NextStepEngine`.
    static func choose(for snapshot: TodaySnapshot, hour: Int) -> TodayNextAction {
        NextStepEngine.choose(for: snapshot, hour: hour)
    }
}
