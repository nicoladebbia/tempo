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
    ///
    /// The nouns the Train screens use are translated through the string catalog (a plural
    /// entry per noun, so Italian gets "1 serie" / "3 serie"). Any other noun, or a call with
    /// an explicit `plural`, keeps the English suffix rule.
    static func text(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        if plural == nil, let translated = translatedText(count, singular) {
            return translated
        }
        return "\(count) \(noun(count, singular, plural: plural))"
    }

    /// Just the noun that agrees with `count`: "exercise" / "exercises".
    static func noun(_ count: Int, _ singular: String, plural: String? = nil) -> String {
        if plural == nil, let translated = translatedNoun(count, singular) {
            return translated
        }
        return count == 1 ? singular : (plural ?? singular + "s")
    }

    private static func translatedText(_ n: Int, _ singular: String) -> String? {
        switch singular {
        case "exercise": String(localized: "\(n) exercises")
        case "set": String(localized: "\(n) sets")
        case "rep": String(localized: "\(n) reps")
        case "round": String(localized: "\(n) rounds")
        case "move": String(localized: "\(n) moves")
        case "change": String(localized: "\(n) changes")
        case "day": String(localized: "\(n) days")
        case "match": String(localized: "\(n) matches")
        case "workout": String(localized: "\(n) workouts")
        case "record": String(localized: "\(n) records")
        case "lift": String(localized: "\(n) lifts")
        case "PR": String(localized: "\(n) PRs")
        default: nil
        }
    }

    private static func translatedNoun(_ n: Int, _ singular: String) -> String? {
        let one = n == 1
        return switch singular {
        case "exercise": one ? String(localized: "exercise", comment: "Noun after a count, singular") : String(localized: "exercises", comment: "Noun after a count, plural")
        case "set": one ? String(localized: "set", comment: "Noun after a count, singular (a set of reps)") : String(localized: "sets", comment: "Noun after a count, plural (sets of reps)")
        case "rep": one ? String(localized: "rep", comment: "Noun after a count, singular (repetition)") : String(localized: "reps", comment: "Noun after a count, plural (repetitions)")
        case "edit": one ? String(localized: "edit", comment: "Noun after a count, singular (a change made by the trainer)") : String(localized: "edits", comment: "Noun after a count, plural (changes made by the trainer)")
        case "session": one ? String(localized: "session", comment: "Noun after a count, singular (lowercase)") : String(localized: "sessions", comment: "Noun after a count, plural (lowercase)")
        case "record": one ? String(localized: "record", comment: "Noun after a count, singular (personal record)") : String(localized: "records", comment: "Noun after a count, plural (personal records)")
        case "lift": one ? String(localized: "lift", comment: "Noun after a count, singular (an exercise such as squat)") : String(localized: "lifts", comment: "Noun after a count, plural (exercises such as squat)")
        case "Workout": one ? String(localized: "Workout", comment: "Stat label under a count, singular") : String(localized: "Workouts", comment: "Stat label under a count, plural")
        case "Set": one ? String(localized: "Set", comment: "Stat label under a count, singular (a set of reps)") : String(localized: "Sets", comment: "Stat label under a count, plural (sets of reps)")
        case "Session": one ? String(localized: "Session", comment: "Stat label under a count, singular") : String(localized: "Sessions", comment: "Stat label under a count, plural")
        default: nil
        }
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
