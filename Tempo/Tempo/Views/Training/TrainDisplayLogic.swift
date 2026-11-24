//
// TrainDisplayLogic.swift
// Tempo
//
// Small pure helpers behind the Train screens' wording and visibility rules,
// kept out of the view bodies so they can be unit-tested: counts with their
// noun, the coach's modality as a readable name, the calendar window that is
// still ahead of us, and when the Start workout bar may show.
//

import Foundation

// MARK: - TrainCount

enum TrainCount {
    /// "1 exercise", "6 exercises". `plural` defaults to the singular plus "s".
    static func text(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        "\(count) \(noun(count, singular, plural: plural))"
    }

    /// Just the noun that agrees with `count`: "exercise" / "exercises".
    static func noun(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        count == 1 ? singular : (plural ?? singular + "s")
    }
}

// MARK: - TrainModalityName

enum TrainModalityName {
    /// The coach's modality label as a person would read it. The brain sends a
    /// free string ("full_body", "Push", "zone 2 run"), so "full_body".capitalized
    /// used to print "Full_Body". A known workout type uses its own display
    /// name; anything else loses its underscores and is capitalised.
    static func displayName(_ modality: String) -> String {
        let trimmed = modality.trimmingCharacters(in: .whitespacesAndNewlines)
        let spaced = trimmed.replacingOccurrences(of: "_", with: " ")
        if let type = WorkoutType(rawValue: trimmed.lowercased()) {
            return type.displayName
        }
        return spaced.capitalized
    }
}

// MARK: - TrainWindowMath

enum TrainWindowMath {
    /// What is left of a suggested workout window once the clock has moved on.
    /// The calendar service builds the window from 08:00, so by the evening it
    /// can sit entirely in the past. The start moves up to `now` (rounded up
    /// to the next 5 minutes) and a window with less than `minimum` left is
    /// dropped, so the card never offers a time that has already gone.
    static func upcoming(
        _ window: DateInterval,
        now: Date,
        minimum: TimeInterval = 45 * 60,
        calendar: Calendar = .current
    ) -> DateInterval? {
        guard window.end > now else {
            return nil
        }
        var start = window.start
        if start < now {
            let step: TimeInterval = 5 * 60
            let rounded = (now.timeIntervalSinceReferenceDate / step).rounded(.up) * step
            start = Date(timeIntervalSinceReferenceDate: rounded)
        }
        guard window.end.timeIntervalSince(start) >= minimum else {
            return nil
        }
        return DateInterval(start: start, end: window.end)
    }
}

// MARK: - TrainStartBar

enum TrainStartBar {
    /// The floating Start workout bar: only on a loggable gym day, never while
    /// loading, never under the bedtime card and never under the Paused card
    /// (that card replaces the whole day, so a start button would contradict it).
    static func isVisible(
        canStartWorkout: Bool,
        isLoading: Bool,
        showsBedtimeCard: Bool,
        showsPausedCard: Bool
    ) -> Bool {
        canStartWorkout && !isLoading && !showsBedtimeCard && !showsPausedCard
    }
}
