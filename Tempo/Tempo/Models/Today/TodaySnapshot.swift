//
// TodaySnapshot.swift
// Tempo
//
// What the Today screen draws, as one plain value. The screen renders a
// `TodaySnapshot` and nothing else, so the same view can draw live numbers or
// the copy saved on disk from the last time the app was open. That is what
// lets Today show real content in its first frame.
//
// The numbers come from DashboardViewModel and the stores each tab owns. The
// wording and the "next action" choice live here as pure functions so they can
// be tested without a simulator.
//

import Foundation

// MARK: - TodaySnapshot

struct TodaySnapshot: Codable, Equatable {
    /// Start of the day these numbers belong to.
    var day: Date
    var firstName: String?
    var score: Int?
    var workout: Workout
    var recovery: Recovery
    var fuel: Fuel
    var tasks: [TaskItem]
    var study: Study
    var streakDays: Int
    var steps: Int?
    var stepsTarget: Int
    /// False until Health or a wearable has given the Move numbers.
    var moveConnected: Bool
    var nextMeal: Meal?

    struct Workout: Codable, Equatable {
        enum Status: String, Codable {
            case none
            case planned
            case completed
            case rest
        }

        var status: Status
        var name: String?
        var inProgress: Bool
        var durationMinutes: Int?
    }

    struct Recovery: Codable, Equatable {
        /// 1...100, nil when no source has a score. Never 0.
        var score: Int?
        var sleepHours: Double?
        var sleepPerformance: Int?
        var hrv: Int?
        var restingHR: Int?
        /// A wearable or Health is feeding recovery.
        var hasSource: Bool
    }

    struct Fuel: Codable, Equatable {
        var calories: Int?
        var calorieTarget: Int?
        var protein: Int?
        var proteinTarget: Int?
        var carbs: Int?
        var carbsTarget: Int?
        var fat: Int?
        var fatTarget: Int?
        var waterMl: Int
        var waterTargetMl: Int
    }

    struct TaskItem: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
        var done: Bool
    }

    struct Study: Codable, Equatable {
        var minutes: Int
        var targetMinutes: Int
        var nextExam: String?
    }

    struct Meal: Codable, Equatable {
        var id: UUID
        var name: String
        /// "HH:mm"
        var time: String
        var calories: Int
        var protein: Int
        /// Inside the prep-to-eat window right now.
        var imminent: Bool
    }

    var tasksDone: Int {
        tasks.count(where: \.done)
    }

    var tasksLeft: Int {
        tasks.count - tasksDone
    }

    var studyLeft: Int {
        max(study.targetMinutes - study.minutes, 0)
    }

    /// The same snapshot seen on a later day: who you are and your targets
    /// still hold, but yesterday's progress must not be shown as today's.
    func carried(to newDay: Date) -> TodaySnapshot {
        guard newDay != day else {
            return self
        }
        var copy = self
        copy.day = newDay
        copy.score = nil
        copy.workout = Workout(status: .none, name: nil, inProgress: false, durationMinutes: nil)
        copy.recovery = Recovery(
            score: nil, sleepHours: nil, sleepPerformance: nil, hrv: nil, restingHR: nil,
            hasSource: recovery.hasSource
        )
        copy.fuel.calories = nil
        copy.fuel.protein = nil
        copy.fuel.carbs = nil
        copy.fuel.fat = nil
        copy.fuel.waterMl = 0
        copy.tasks = tasks.map { TaskItem(id: $0.id, title: $0.title, done: false) }
        copy.study.minutes = 0
        copy.steps = nil
        copy.nextMeal = nil
        return copy
    }
}

// MARK: - TodayPhase

/// What Today puts on screen. The loading placeholder is only ever chosen
/// when there is neither live data nor a saved snapshot: a first-ever launch.
enum TodayPhase: Equatable {
    case content(TodaySnapshot, isLive: Bool)
    case firstLoad
    case failed(String)

    static func resolve(live: TodaySnapshot?, cached: TodaySnapshot?, error: String?) -> TodayPhase {
        if let live {
            return .content(live, isLive: true)
        }
        if let cached {
            return .content(cached, isLive: false)
        }
        if let error {
            return .failed(error)
        }
        return .firstLoad
    }

    var isLoading: Bool {
        self == .firstLoad
    }
}

// MARK: - TodayGreeting

enum TodayGreeting {
    /// The name onboarding falls back to when none was given.
    static let placeholderName = "Athlete"

    static func text(hour: Int, name: String?) -> String {
        let part = switch hour {
        case 5 ..< 12: "Good morning"
        case 12 ..< 18: "Good afternoon"
        case 18 ..< 23: "Good evening"
        default: "Still up"
        }
        guard let first = firstName(from: name) else {
            return part
        }
        return "\(part), \(first)"
    }

    /// "Nicola Debbia" → "Nicola"; the placeholder and blanks → nil.
    static func firstName(from name: String?) -> String? {
        guard let first = name?.split(separator: " ").first.map(String.init),
              first != placeholderName
        else {
            return nil
        }
        return first
    }
}

// MARK: - TodayStatus

/// The one line under the mood word. Built from what is already known about
/// the day; it adds no scoring of its own.
enum TodayStatus {
    static let lowRecovery = 34

    static func line(for snapshot: TodaySnapshot) -> String {
        var left: [String] = []
        if snapshot.workout.status == .planned {
            let name = snapshot.workout.name ?? "Your session"
            left.append(snapshot.workout.inProgress ? "\(name) in progress" : "\(name) session")
        }
        if snapshot.tasksLeft > 0 {
            left.append(snapshot.tasksLeft == 1 ? "1 task" : "\(snapshot.tasksLeft) tasks")
        }
        if snapshot.studyLeft > 0 {
            left.append("\(snapshot.studyLeft) min of study")
        }

        if let recovery = snapshot.recovery.score, recovery < lowRecovery, snapshot.workout.status == .planned {
            return "Recovery is low at \(recovery)%. Go lighter today."
        }
        guard snapshot.score != nil else {
            return left.isEmpty
                ? "Log a meal or a session and your score appears here."
                : "Still to do: \(joined(left))."
        }
        if left.isEmpty {
            return snapshot.workout.status == .rest
                ? "Rest day, list cleared. Eat and sleep well."
                : "Everything on the list is done."
        }
        return "Still to do: \(joined(left))."
    }

    private static func joined(_ parts: [String]) -> String {
        switch parts.count {
        case 0: ""
        case 1: parts[0]
        default: parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
        }
    }
}

// MARK: - TodayNextAction

/// The single thing to do now.
enum TodayNextAction: Equatable {
    case workout(name: String, resume: Bool)
    case meal(TodaySnapshot.Meal)
    case rest
    case focus(minutesLeft: Int)
    case tasks(left: Int)
    case setUpTasks
    case allDone

    /// After this hour an unfinished session gives way to the next meal.
    static let lateHour = 21

    static func choose(for snapshot: TodaySnapshot, hour: Int) -> TodayNextAction {
        let workout = snapshot.workout
        if workout.status == .planned {
            // A session already started always wins; otherwise late in the
            // day the next meal is the more useful thing to show.
            if workout.inProgress || hour < lateHour || snapshot.nextMeal == nil {
                return .workout(name: workout.name ?? "Workout", resume: workout.inProgress)
            }
        }
        if let meal = snapshot.nextMeal, meal.imminent || workout.status != .rest {
            return .meal(meal)
        }
        if workout.status == .rest {
            return .rest
        }
        if snapshot.studyLeft > 0 {
            return .focus(minutesLeft: snapshot.studyLeft)
        }
        if snapshot.tasksLeft > 0 {
            return .tasks(left: snapshot.tasksLeft)
        }
        if snapshot.tasks.isEmpty {
            return .setUpTasks
        }
        return .allDone
    }
}

// MARK: - TodayCache

/// The last Today that was drawn, kept on disk so the next launch can draw it
/// before anything has loaded.
struct TodayCache {
    let url: URL

    static let shared = TodayCache(
        url: URL.cachesDirectory.appending(path: "today-snapshot.json")
    )

    /// The saved snapshot, adjusted for `now` (yesterday's progress is cleared).
    func load(now: Date = Date(), calendar: Calendar = .current) -> TodaySnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(TodaySnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot.carried(to: calendar.startOfDay(for: now))
    }

    func save(_ snapshot: TodaySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
