//
// WeeklyRoutine.swift
// Tempo
//
// The user's real week, per weekday: wake / leave home / back home / bed,
// training, and fixed events (classes, work, meals out with friends at a
// given place). Captured once by Fuel setup (talk or type) and read by the
// weekly meal planner every Sunday so meals land where the user actually is.
// Stored as JSON on UserDailyPlanProfile.weeklyRoutineJSON.
//

import Foundation

// MARK: - WeeklyRoutine

struct WeeklyRoutine: Codable, Equatable, Sendable {
    /// Always 7 entries, Monday (1) … Sunday (7).
    var days: [DayRoutine]
    /// Places the user goes to (campus, office, gym) with the restaurants they use there.
    var places: [RoutinePlace]

    init(days: [DayRoutine] = [], places: [RoutinePlace] = []) {
        self.days = (1 ... 7).map { weekday in
            days.first { $0.weekday == weekday } ?? DayRoutine(weekday: weekday)
        }
        self.places = places
    }

    static let empty = WeeklyRoutine()

    subscript(weekday: Int) -> DayRoutine {
        get { days.first { $0.weekday == weekday } ?? DayRoutine(weekday: weekday) }
        set {
            if let index = days.firstIndex(where: { $0.weekday == weekday }) {
                days[index] = newValue
            }
        }
    }

    var isEmpty: Bool {
        places.isEmpty && days.allSatisfy(\.isEmpty)
    }

    func place(id: UUID?) -> RoutinePlace? {
        id.flatMap { id in places.first { $0.id == id } }
    }

    /// The wake time the user has on most weekdays (Mon–Fri), else on any day.
    var typicalWakeMinutes: Int? {
        Self.mostCommon(days.filter { $0.weekday <= 5 }.compactMap(\.wakeMinutes))
            ?? Self.mostCommon(days.compactMap(\.wakeMinutes))
    }

    var typicalBedMinutes: Int? {
        Self.mostCommon(days.filter { $0.weekday <= 5 }.compactMap(\.bedMinutes))
            ?? Self.mostCommon(days.compactMap(\.bedMinutes))
    }

    var trainingDaysPerWeek: Int {
        days.filter { $0.training != nil }.count
    }

    /// Ties go to the earliest time, so the result is stable.
    private static func mostCommon(_ values: [Int]) -> Int? {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }?.key
    }
}

// MARK: - DayRoutine

struct DayRoutine: Codable, Equatable, Sendable, Identifiable {
    /// 1 = Monday … 7 = Sunday.
    var weekday: Int
    var wakeMinutes: Int?
    var leaveHomeMinutes: Int?
    var backHomeMinutes: Int?
    var bedMinutes: Int?
    var training: TrainingSlot?
    var events: [RoutineEvent] = []

    var id: Int {
        weekday
    }

    var isEmpty: Bool {
        wakeMinutes == nil && leaveHomeMinutes == nil && backHomeMinutes == nil
            && bedMinutes == nil && training == nil && events.isEmpty
    }

    var name: String {
        Self.names[(weekday - 1 + 7) % 7]
    }

    var shortName: String {
        String(name.prefix(3))
    }

    static let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
}

// MARK: - TrainingSlot

struct TrainingSlot: Codable, Equatable, Sendable {
    var startMinutes: Int
    var durationMinutes: Int = 60
    /// Free text: "gym — upper", "football practice", "run".
    var kind: String = ""
}

// MARK: - RoutineEvent

struct RoutineEvent: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case classOrWork
        case mealOut
        case other

        var label: String {
            switch self {
            case .classOrWork: "Class / work"
            case .mealOut: "Meal out"
            case .other: "Other"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var title: String
    var startMinutes: Int
    var endMinutes: Int?
    var placeID: UUID?
    /// For meals out: who with ("friends"), and the restaurants to pick from
    /// (in order of preference — the first is the usual one).
    var with: String?
    var restaurants: [String] = []
}

// MARK: - RoutinePlace

struct RoutinePlace: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    /// "FIU Modesto Maidique Campus".
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    /// Restaurants the user eats at here ("Panera Bread", "Chipotle").
    var usualRestaurants: [String] = []

    var hasCoordinate: Bool {
        latitude != nil && longitude != nil
    }
}

// MARK: - RoutineTime

enum RoutineTime {
    /// "13:00" / "7:30" / "1:05 pm" → minutes from midnight. nil when unreadable.
    static func minutes(from text: String?) -> Int? {
        guard var raw = text?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
            return nil
        }
        var offset = 0
        for (suffix, pm) in [("pm", true), ("am", false)] where raw.hasSuffix(suffix) {
            raw = String(raw.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            offset = pm ? 12 * 60 : 0
            if !raw.contains(":") {
                raw += ":00"
            }
            let parts = raw.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (1 ... 12).contains(parts[0]), (0 ..< 60).contains(parts[1]) else {
                return nil
            }
            return (parts[0] % 12) * 60 + parts[1] + offset
        }
        let parts = raw.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0 ..< 24).contains(parts[0]), (0 ..< 60).contains(parts[1]) else {
            return nil
        }
        return parts[0] * 60 + parts[1]
    }

    static func string(_ minutes: Int?) -> String? {
        minutes.map { String(format: "%02d:%02d", ($0 / 60) % 24, $0 % 60) }
    }
}
