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
        "kcal of \(formattedCalorieTarget)"
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
            return "Next: \(nextMeal.mealName) · \(nextMeal.scheduledTime)"
        }
        if lastEatenAt != nil {
            return "Last meal \(formattedLastEaten)"
        }
        return "No meals logged yet"
    }
}

// MARK: - Move

extension MoveQuadrantData {
    /// One-word workout state for the "Workout" row.
    var workoutSummary: String {
        switch workoutStatus {
        case .completed: "Done"
        case .planned: workoutName ?? "Planned"
        case .restDay: "Rest"
        case .none: "--"
        }
    }

    /// Footer line under the steps bar: "Goal 10,000".
    var stepsGoalText: String {
        "Goal \(NumberFormatter.localizedString(from: NSNumber(value: stepsTarget), number: .decimal))"
    }
}

// MARK: - Mind

extension MindQuadrantData {
    var hasHitStudyTarget: Bool {
        studyTargetMinutes > 0 && studyMinutesToday >= studyTargetMinutes
    }

    /// Caption under the study-time hero.
    var studyCaption: String {
        hasHitStudyTarget ? "Target hit" : "Study today"
    }

    /// Footer line under the study bar: "45% of target".
    var studyProgressText: String {
        guard studyTargetMinutes > 0 else {
            return "No target set"
        }
        return "\(Int((studyProgress * 100).rounded()))% of target"
    }
}
