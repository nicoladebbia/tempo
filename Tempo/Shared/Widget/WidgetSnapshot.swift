//
// WidgetSnapshot.swift
// Tempo
//
// What the home-screen and lock-screen widgets draw, as one plain value. The
// app writes it into the shared app group; the widget extension reads it. One
// file, compiled into both targets, so the writer and the reader cannot drift
// apart. It is written as a single JSON blob, so a widget never reads half of
// an update.
//
// The numbers come from the same `TodaySnapshot` the Today screen draws
// (`WidgetSnapshot+Today.swift`), so a widget can never show a different
// figure than Today does. Nothing here is invented: a field is nil until the
// app has a real value for it.
//

import Foundation

// MARK: - WidgetDestination

/// Where a tap on a widget lands.
enum WidgetDestination: String, Codable, Sendable, CaseIterable {
    case today
    case train
    case fuel
    case arena

    /// `tempo://open/<destination>`, handled by `TempoDeepLink`.
    var url: URL {
        URL(string: "tempo://open/\(rawValue)") ?? URL(fileURLWithPath: "/")
    }
}

// MARK: - WidgetSnapshot

struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let appGroupID = "group.app.tempo.Tempo"
    static let storageKey = "widget.snapshot.v2"

    /// Start of the day these numbers belong to.
    var day: Date
    var writtenAt: Date
    /// 0...100 day score, nil until the day has one.
    var score: Int?
    var tasksDone: Int
    var tasksTotal: Int
    var calories: Int?
    var calorieTarget: Int?
    var protein: Int?
    var proteinTarget: Int?
    var carbs: Int?
    var carbsTarget: Int?
    var fat: Int?
    var fatTarget: Int?
    var waterMl: Int
    /// nil until the app has worked out the day's target.
    var waterTargetMl: Int?
    var next: Next?

    // MARK: Next action

    /// The one thing to do now: the same choice as the Today hero.
    struct Next: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case workout
            case meal
            case rest
            case firstMeal
            case focus
            case tasks
            case setUpTasks
            case allDone
        }

        var kind: Kind
        var title: String
        var detail: String
        /// The small line beside the title: the meal's "12:30" or the session's "55 min".
        var trailing: String?
        var destination: WidgetDestination
    }

    // MARK: Day handling

    /// A snapshot with nothing in it but the day.
    static func empty(for day: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            day: day, writtenAt: day, score: nil, tasksDone: 0, tasksTotal: 0,
            calories: nil, calorieTarget: nil, protein: nil, proteinTarget: nil,
            carbs: nil, carbsTarget: nil, fat: nil, fatTarget: nil,
            waterMl: 0, waterTargetMl: nil, next: nil
        )
    }

    /// The same snapshot seen on a later day: the targets still hold, but
    /// yesterday's progress must not be shown as today's.
    func carried(to now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        let start = calendar.startOfDay(for: now)
        guard start != day else {
            return self
        }
        var copy = WidgetSnapshot.empty(for: start)
        copy.writtenAt = writtenAt
        copy.calorieTarget = calorieTarget
        copy.proteinTarget = proteinTarget
        copy.carbsTarget = carbsTarget
        copy.fatTarget = fatTarget
        copy.waterTargetMl = waterTargetMl
        return copy
    }

    /// This snapshot with a new water total (an intent logged water while the
    /// app was in the background). A snapshot from an earlier day starts over.
    func updatingWater(ml: Int, targetMl: Int?, now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        var copy = carried(to: now, calendar: calendar)
        copy.waterMl = ml
        copy.waterTargetMl = targetMl ?? copy.waterTargetMl
        copy.writtenAt = now
        return copy
    }

    /// 0...1 progress, nil when there is no target to measure against.
    static func fraction(_ value: Int?, of target: Int?) -> Double? {
        guard let value, let target, target > 0 else {
            return nil
        }
        return min(max(Double(value) / Double(target), 0), 1)
    }

    var waterFraction: Double? {
        Self.fraction(waterMl, of: waterTargetMl)
    }

    // MARK: Storage

    /// Reads what the app last wrote; nil when it has never written one.
    static func read(from defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)) -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Writes this snapshot. Returns false when it could not be encoded or stored.
    @discardableResult
    func write(to defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)) -> Bool {
        guard let defaults, let data = try? JSONEncoder().encode(self) else {
            return false
        }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }
}
