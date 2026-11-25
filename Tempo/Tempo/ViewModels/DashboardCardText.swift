//
// DashboardCardText.swift
// Tempo
//
// Created by Tempo on 25/09/2026.
//

import Foundation

// Display strings for the four Dashboard quadrant cards. Every card uses the
// Body card's layout (hero value → caption → divider → three metric rows →
// footer bar), so each quadrant exposes the same set of short strings here.

// MARK: - Fuel

extension FuelQuadrantData {
    /// Caption under the calorie hero: "kcal of 2,400".
    var caloriesCaption: String {
        String(localized: "kcal of \(formattedCalorieTarget)")
    }

    /// "142 / 180g" for a macro row. A missing intake reads as 0 — the card
    /// always has a target, so "0 / 180g" is more useful than "--".
    static func macroProgress(current: Int?, target: Int?) -> String {
        guard let target else {
            return "--"
        }
        return "\(current ?? 0) / \(target)g"
    }

    /// Footer line: the next meal if one is planned, else when the last meal
    /// was eaten, else a nudge to log one.
    var cardFootnote: String {
        if let nextMeal {
            return String(localized: "Next: \(nextMeal.mealName) · \(nextMeal.scheduledTime)")
        }
        if lastEatenAt != nil {
            return String(localized: "Last meal \(formattedLastEaten)")
        }
        return String(localized: "No meals logged yet")
    }
}

// MARK: - Move

extension MoveQuadrantData {
    /// Hero line: today's session name, or the day's state when there's none.
    var workoutHeadline: String {
        switch workoutStatus {
        case .completed, .planned: workoutName ?? String(localized: "Workout")
        case .restDay: String(localized: "Rest Day")
        case .none: String(localized: "No workout")
        }
    }

    /// Caption under the workout hero: "Done · 48m", "Planned · ~52 min"…
    var workoutCaption: String {
        switch workoutStatus {
        case .completed:
            workoutDurationMinutes == nil ? String(localized: "Done") : String(localized: "Done · \(formattedWorkoutDuration)")
        case .planned:
            workoutDurationMinutes.map { String(localized: "Planned · ~\($0) min") } ?? String(localized: "Planned for today")
        case .restDay: String(localized: "Recovery is training.")
        case .none: String(localized: "Add one or skip.")
        }
    }

    /// Footer line under the steps bar: "Goal 10,000".
    var stepsGoalText: String {
        String(localized: "Goal \(NumberFormatter.localizedString(from: NSNumber(value: stepsTarget), number: .decimal))")
    }
}

// MARK: - Mind

extension MindQuadrantData {
    var hasHitStudyTarget: Bool {
        studyTargetMinutes > 0 && studyMinutesToday >= studyTargetMinutes
    }

    /// Caption under the study-time hero.
    var studyCaption: String {
        hasHitStudyTarget ? String(localized: "Target hit") : String(localized: "Study today")
    }

    /// Footer line under the study bar: "45% of target".
    var studyProgressText: String {
        guard studyTargetMinutes > 0 else {
            return String(localized: "No target set")
        }
        return String(localized: "\(Int((studyProgress * 100).rounded()))% of target")
    }
}
