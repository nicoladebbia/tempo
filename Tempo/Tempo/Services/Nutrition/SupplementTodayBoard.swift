//
// SupplementTodayBoard.swift
// Tempo
//
// Today's supplement card as plain data: the schedule engine's doses grouped
// by time of day (Morning / With meals / Evening), each row carrying its
// tick state, the time it was taken, the macros a tick counts and a
// running-low flag. Pure — the card view only draws it.
//

import Foundation

// MARK: - SupplementPeriod

enum SupplementPeriod: Int, CaseIterable, Sendable {
    case morning
    case withMeals
    case evening

    var title: String {
        switch self {
        case .morning: "Morning"
        case .withMeals: "With meals"
        case .evening: "Evening"
        }
    }

    var icon: String {
        switch self {
        case .morning: "sunrise.fill"
        case .withMeals: "fork.knife"
        case .evening: "moon.stars.fill"
        }
    }

    /// Lunch and dinner doses ride with a meal; waking and breakfast are the
    /// morning; bedtime is the evening. Training and pinned doses go by the
    /// clock (before noon / after 17:30 / in between).
    static func period(for dose: SupplementDose) -> SupplementPeriod {
        switch dose.anchor {
        case .wake, .breakfast: return .morning
        case .lunch, .dinner: return .withMeals
        case .bedtime: return .evening
        case .preTraining, .postTraining, nil: break
        }
        if dose.minutes < 12 * 60 {
            return .morning
        }
        return dose.minutes >= 17 * 60 + 30 ? .evening : .withMeals
    }
}

// MARK: - SupplementBoardRow

struct SupplementBoardRow: Identifiable, Equatable {
    let dose: SupplementDose
    let isTaken: Bool
    /// When the tick happened (nil when not taken).
    let takenAt: Date?
    /// What a tick adds to today's totals (nil for creatine, vitamins…).
    let macros: MealMacros?
    /// Estimated days of supply left, only when it's low enough to flag.
    let lowDaysLeft: Int?

    var id: UUID {
        dose.supplementID
    }

    /// "25 g protein · 120 kcal", or nil when the dose carries no macros.
    var macrosLine: String? {
        guard let macros, macros.calories > 0 || macros.protein > 0 else {
            return nil
        }
        var parts: [String] = []
        if macros.protein >= 1 {
            parts.append("\(Int(macros.protein.rounded())) g protein")
        }
        if macros.calories >= 1 {
            parts.append("\(Int(macros.calories.rounded())) kcal")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - SupplementBoardSection

struct SupplementBoardSection: Identifiable, Equatable {
    let period: SupplementPeriod
    let rows: [SupplementBoardRow]

    var id: Int {
        period.rawValue
    }
}

// MARK: - SupplementTodayBoard

struct SupplementTodayBoard: Equatable {
    let sections: [SupplementBoardSection]
    /// Doses the plan says to skip today (shown as one quiet line).
    let skipped: [SupplementDose]

    var total: Int {
        sections.reduce(0) { $0 + $1.rows.count }
    }

    var takenCount: Int {
        sections.reduce(0) { $0 + $1.rows.filter(\.isTaken).count }
    }

    var allTaken: Bool {
        total > 0 && takenCount == total
    }

    /// The not-yet-taken rows with a running-low flag (the inline reorder chips).
    var lowRows: [SupplementBoardRow] {
        sections.flatMap(\.rows).filter { $0.lowDaysLeft != nil }
    }

    /// Doses are grouped by period; inside a period the not-yet-taken come in
    /// clock order and taken ones keep their clock order too (rows don't jump
    /// around under the finger on a tick).
    static func build(
        doses: [SupplementDose],
        takenAt: [UUID: Date],
        macros: [UUID: MealMacros] = [:],
        daysLeft: [UUID: Int] = [:]
    ) -> SupplementTodayBoard {
        let take = doses.filter(\.take)
        let skipped = doses.filter { !$0.take }.sorted { ($0.minutes, $0.name) < ($1.minutes, $1.name) }
        let sections = SupplementPeriod.allCases.compactMap { period -> SupplementBoardSection? in
            let rows = take
                .filter { SupplementPeriod.period(for: $0) == period }
                .sorted { ($0.minutes, $0.name) < ($1.minutes, $1.name) }
                .map { dose in
                    SupplementBoardRow(
                        dose: dose,
                        isTaken: takenAt[dose.supplementID] != nil,
                        takenAt: takenAt[dose.supplementID],
                        macros: macros[dose.supplementID],
                        lowDaysLeft: daysLeft[dose.supplementID]
                    )
                }
            return rows.isEmpty ? nil : SupplementBoardSection(period: period, rows: rows)
        }
        return SupplementTodayBoard(sections: sections, skipped: skipped)
    }
}
