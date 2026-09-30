//
// WorkoutPlan+Composite.swift
// Tempo
//
// Display text for a composite day (soccer done + extra gym session) so Today,
// Week Plan, Dashboard and history all read the same words.
//

import Foundation

extension WorkoutPlan {
    /// "10:00" for minutes since midnight (24 h, matches the plan copy).
    static func clockText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    /// "Football 10:00 ✓" — the finished companion part, nil off a composite day.
    var companionPartText: String? {
        guard let companion = companionType else {
            return nil
        }
        var text = companion.displayName
        if let start = companionStartMin {
            text += " \(Self.clockText(start))"
        }
        return companionCompleted ? text + " ✓" : text
    }

    /// "Push 18:00" — the gym anchor with its start time when known.
    var anchorPartText: String {
        var text = type.displayName
        if let start = scheduledStartMin {
            text += " \(Self.clockText(start))"
        }
        return text
    }

    /// "Football 10:00 ✓ · Push 18:00" on a composite day, else the plain type name.
    var daySummaryText: String {
        guard let companion = companionPartText else {
            return type.displayName
        }
        return "\(companion) · \(anchorPartText)"
    }
}
