//
// GoalEngine.swift
// Tempo
//
// Where a goal stands, by the straight line from the first reading to the
// target on the target date. Pure: numbers in, a verdict out.
//
//   expected(today) = start + (target - start) * (days gone / days in all)
//
// A reading within a tenth of the whole distance of that line is "on track";
// further along it is "ahead", further back "behind". Reaching the target
// ends the question whatever the date says.
//

import Foundation
import SwiftData

// MARK: - GoalProgress

struct GoalProgress: Equatable {
    enum Pace: Equatable {
        case ahead
        case onTrack
        case behind
        case reached
        /// No reading yet, so nothing can be said.
        case noReading

        var title: String {
            switch self {
            case .ahead: "Ahead"
            case .onTrack: "On track"
            case .behind: "Behind"
            case .reached: "Reached"
            case .noReading: "No reading yet"
            }
        }
    }

    let start: Double
    let target: Double
    let current: Double?
    /// Where the straight line says the reading should be today.
    let expected: Double
    /// How far from start to target the reading has come, 0 to 1.
    let fraction: Double
    let pace: Pace
    /// Whole days from today to the target date; negative once it has passed.
    let daysLeft: Int
}

// MARK: - GoalEngine

enum GoalEngine {
    /// A reading this close to the line (as a share of the whole distance) is on track.
    static let tolerance = 0.10

    static func evaluate(
        start: Double,
        startDate: Date,
        target: Double,
        targetDate: Date,
        current: Double?,
        now: Date,
        higherIsBetter: Bool? = nil,
        calendar: Calendar = .current
    ) -> GoalProgress {
        // Whole calendar days, so a daylight-saving change never nudges the line
        // and it moves once a day, not by the hour.
        let startDay = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)
        let total = calendar.dateComponents([.day], from: startDay, to: calendar.startOfDay(for: targetDate)).day ?? 0
        let elapsed = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
        let share = total > 0 ? min(max(Double(elapsed) / Double(total), 0), 1) : 1
        let expected = start + (target - start) * share
        let daysLeft = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: targetDate)).day ?? 0

        guard let current else {
            return GoalProgress(
                start: start, target: target, current: nil, expected: expected,
                fraction: 0, pace: .noReading, daysLeft: daysLeft
            )
        }

        let distance = target - start
        // 1 when a bigger number is better, -1 when a smaller one is. A lift is
        // always the first and a run time always the second, even when the first
        // reading is already past the target; only a body weight (to lose or to
        // gain) takes its direction from where it starts.
        let direction: Double = higherIsBetter.map { $0 ? 1 : -1 } ?? (distance >= 0 ? 1 : -1)

        let pace: GoalProgress.Pace
        let fraction: Double
        if (current - target) * direction >= 0 {
            pace = .reached
            fraction = 1
        } else {
            fraction = abs(distance) < .ulpOfOne ? 1 : min(max((current - start) / distance, 0), 1)
            let gap = (current - expected) * direction
            let band = abs(distance) * tolerance
            pace = gap > band ? .ahead : (gap < -band ? .behind : .onTrack)
        }
        return GoalProgress(
            start: start, target: target, current: current, expected: expected,
            fraction: fraction, pace: pace, daysLeft: daysLeft
        )
    }

    /// The same, read from a stored goal and the person's latest reading.
    /// A goal set before any reading existed starts at the first one.
    static func evaluate(goal: Goal, current: Double?, now: Date, calendar: Calendar = .current) -> GoalProgress {
        evaluate(
            start: goal.startValue ?? current ?? goal.targetValue,
            startDate: goal.startDate,
            target: goal.targetValue,
            targetDate: goal.targetDate,
            current: current,
            now: now,
            higherIsBetter: goal.kind == .bodyWeight ? nil : goal.kind == .liftE1RM,
            calendar: calendar
        )
    }
}

// MARK: - GoalReader

/// The latest reading for a goal, read from what the app already stores.
@MainActor
enum GoalReader {
    /// A run counts toward a distance when it is at least 95% as long.
    static let runDistanceSlack = 0.95

    static func activeGoal(in context: ModelContext) -> Goal? {
        var descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate<Goal> { $0.isActive == true },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// kg for a weight or a lift, seconds for a run. nil when nothing is logged.
    static func current(for goal: Goal, in context: ModelContext) -> Double? {
        switch goal.kind {
        case .bodyWeight:
            latestWeightKg(in: context)
        case .liftE1RM:
            bestE1RM(named: goal.exerciseName, in: context)
        case .runTime:
            bestRunSeconds(distanceKm: goal.runDistanceKm, in: context)
        }
    }

    static func latestWeightKg(in context: ModelContext) -> Double? {
        var descriptor = FetchDescriptor<BodyComposition>(
            predicate: #Predicate<BodyComposition> { $0.weightKg != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.weightKg
    }

    /// The highest estimated one-rep max logged for the lift. Same number the
    /// Exercise Library shows next to the lift.
    static func bestE1RM(named name: String?, in context: ModelContext) -> Double? {
        guard let name, !name.isEmpty else {
            return nil
        }
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate<Exercise> { $0.name == name })
        guard let exercise = (try? context.fetch(descriptor))?.first else {
            return nil
        }
        let best = (exercise.history ?? []).compactMap(\.estimated1RM).max()
        return (best ?? 0) > 0 ? best : nil
    }

    /// The fastest run at least as long as the distance, scaled to exactly
    /// that distance at its average pace.
    static func bestRunSeconds(distanceKm: Double?, in context: ModelContext) -> Double? {
        guard let distanceKm, distanceKm > 0 else {
            return nil
        }
        let meters = distanceKm * 1000
        let minMeters = meters * runDistanceSlack
        let descriptor = FetchDescriptor<RunSession>(predicate: #Predicate<RunSession> { $0.distanceMeters >= minMeters })
        let runs = (try? context.fetch(descriptor)) ?? []
        return runs
            .filter { $0.durationSeconds > 0 }
            .map { Double($0.durationSeconds) / $0.distanceMeters * meters }
            .min()
    }
}

// MARK: - GoalFormat

/// How a goal's numbers read.
enum GoalFormat {
    /// "62.5 kg" or "155 lbs" for weights and lifts, "24:30" for a run.
    static func value(_ value: Double, kind: GoalKind, unit: WeightUnit) -> String {
        switch kind {
        case .bodyWeight,
             .liftE1RM: WeightFormat.text(kg: value, unit: unit)
        case .runTime: clock(seconds: value)
        }
    }

    /// 1470 -> "24:30", 3725 -> "1:02:05".
    static func clock(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// "5 km", "21.1 km".
    static func distance(km: Double) -> String {
        km == km.rounded() ? "\(Int(km)) km" : String(format: "%.1f km", km)
    }

    /// "12 days left", "Today", "3 days over".
    static func daysLeft(_ days: Int) -> String {
        switch days {
        case 0: "Due today"
        case 1: "1 day left"
        case 2...: "\(days) days left"
        case -1: "1 day over"
        default: "\(-days) days over"
        }
    }

    /// One line a person can read: "Bench press 100 kg by 1 Mar".
    static func headline(for goal: Goal, unit: WeightUnit) -> String {
        let target = value(goal.targetValue, kind: goal.kind, unit: unit)
        switch goal.kind {
        case .bodyWeight: return "Reach \(target)"
        case .liftE1RM: return "\(goal.exerciseName ?? "Lift") \(target)"
        case .runTime: return "\(goal.runDistanceKm.map(distance(km:)) ?? "Run") in \(target)"
        }
    }
}

// MARK: - GoalSnapshot

/// A goal, where it stands, and every word the screens need. Read once and drawn
/// by the Today card and the progress chips, so they always say the same thing.
struct GoalSnapshot: Equatable, Identifiable {
    let id: UUID
    let kind: GoalKind
    let progress: GoalProgress
    /// "Reach 75 kg", "Barbell Bench Press 100 kg", "5 km in 24:30".
    let headline: String
    /// "82.4 kg" or "No reading yet".
    let nowText: String
    let targetText: String
    let daysLeftText: String

    /// One short line: "Ahead of your line".
    var paceLine: String {
        switch progress.pace {
        case .ahead: "Ahead of your line"
        case .onTrack: "On track"
        case .behind: "Behind your line"
        case .reached: "Goal reached"
        case .noReading: "No reading yet"
        }
    }
}

extension GoalReader {
    /// The active goal as a snapshot, optionally only for some kinds. The first
    /// reading after a goal is set becomes its starting point.
    static func snapshot(
        kinds: Set<GoalKind>? = nil, unit: WeightUnit, now: Date = Date(), in context: ModelContext
    ) -> GoalSnapshot? {
        guard let goal = activeGoal(in: context), kinds?.contains(goal.kind) ?? true else {
            return nil
        }
        let current = current(for: goal, in: context)
        if goal.startValue == nil, let current {
            goal.startValue = current
            goal.startDate = now
            try? context.save()
        }
        let progress = GoalEngine.evaluate(goal: goal, current: current, now: now)
        return GoalSnapshot(
            id: goal.id,
            kind: goal.kind,
            progress: progress,
            headline: GoalFormat.headline(for: goal, unit: unit),
            nowText: current.map { GoalFormat.value($0, kind: goal.kind, unit: unit) } ?? "No reading yet",
            targetText: GoalFormat.value(goal.targetValue, kind: goal.kind, unit: unit),
            daysLeftText: GoalFormat.daysLeft(progress.daysLeft)
        )
    }
}
