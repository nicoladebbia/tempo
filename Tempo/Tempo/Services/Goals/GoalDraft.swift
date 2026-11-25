//
// GoalDraft.swift
// Tempo
//
// What the person has typed into the goal editor, and whether it makes a goal.
// Pure, so the rules are tested without a screen.
//

import Foundation

struct GoalDraft: Equatable {
    /// The run distances offered, in kilometres.
    static let runDistances: [Double] = [5, 10, 21.1, 42.2]

    enum Problem: Equatable {
        case needsTarget
        case needsExercise
        case needsDate
    }

    var kind: GoalKind = .bodyWeight
    /// A weight or a lift, in the person's own unit.
    var weightText = ""
    var exercise: String?
    var runDistanceKm = 5.0
    var minutesText = ""
    var secondsText = ""
    var targetDate: Date

    init(targetDate: Date) {
        self.targetDate = targetDate
    }

    /// A draft that starts from a saved goal, with numbers shown in `unit`.
    init(goal: Goal, unit: WeightUnit) {
        kind = goal.kind
        targetDate = goal.targetDate
        exercise = goal.exerciseName
        runDistanceKm = goal.runDistanceKm ?? 5
        switch goal.kind {
        case .bodyWeight,
             .liftE1RM:
            weightText = WeightFormat.number(kg: goal.targetValue, unit: unit)
        case .runTime:
            let total = Int(goal.targetValue.rounded())
            minutesText = String(total / 60)
            secondsText = String(total % 60)
        }
    }

    /// Kilograms for a weight or a lift, seconds for a run. nil until it is a real number.
    func targetValue(unit: WeightUnit) -> Double? {
        switch kind {
        case .bodyWeight,
             .liftE1RM:
            guard let value = Self.number(weightText), value > 0 else {
                return nil
            }
            return unit.convert(value, to: .kg)
        case .runTime:
            let minutes = Self.number(minutesText) ?? 0
            let seconds = Self.number(secondsText) ?? 0
            let total = minutes * 60 + seconds
            return total > 0 && minutes >= 0 && seconds >= 0 ? total : nil
        }
    }

    func problem(now: Date, unit: WeightUnit, calendar: Calendar = .current) -> Problem? {
        if kind == .liftE1RM, exercise?.isEmpty != false {
            return .needsExercise
        }
        if targetValue(unit: unit) == nil {
            return .needsTarget
        }
        if calendar.startOfDay(for: targetDate) <= calendar.startOfDay(for: now) {
            return .needsDate
        }
        return nil
    }

    /// True when today's reading already meets the target, so the goal would
    /// start finished: a lift at or above it, a run at or under it, a body
    /// weight within 50 g of it. `current` is in kilograms or seconds.
    func alreadyReached(current: Double?, unit: WeightUnit) -> Bool {
        guard let current, let target = targetValue(unit: unit) else {
            return false
        }
        switch kind {
        case .bodyWeight: return abs(current - target) < 0.05
        case .liftE1RM: return current >= target
        case .runTime: return current <= target
        }
    }

    /// Clears the typed target when the type changes: 83.8 kg of body weight
    /// is not an 83.8 kg squat.
    mutating func clearTarget() {
        weightText = ""
        minutesText = ""
        secondsText = ""
    }

    /// Reads "82,5" and "82.5" alike; anything else is not a number.
    static func number(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else {
            return nil
        }
        return value
    }

    /// Writes the draft into `goal`, starting its line from `start` today.
    func apply(to goal: Goal, unit: WeightUnit, start: Double?, now: Date) {
        goal.kind = kind
        goal.targetValue = targetValue(unit: unit) ?? goal.targetValue
        goal.targetDate = targetDate
        goal.startValue = start
        goal.startDate = now
        goal.exerciseName = kind == .liftE1RM ? exercise : nil
        goal.runDistanceKm = kind == .runTime ? runDistanceKm : nil
        goal.isActive = true
    }
}
