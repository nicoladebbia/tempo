//
// TrainerTestDayDetector.swift
// Tempo
//
// trainer-feedback-tests — detects a trainer-written max/time-trial TEST
// session ("test 1RM", "max test", "5RM", "time trial", "test 30m", "Yo-Yo",
// Italian equivalents) from the day's title/notes and its exercises'
// name/detail/notes text. Pure and side-effect free, like
// `ConditioningTargetParser` — a string that matches nothing known is simply
// not a test, never a crash or a guess beyond the keyword list.
//
// Wired into `TrainerProgramParser.parse` (day-level AND per-exercise) and
// re-checked live on `TrainerProgramReviewView`/`DayEditorView` so a manually
// added/renamed exercise still gets picked up before save.
//

import Foundation

enum TrainerTestDayDetector {
    /// Rep-max wording ("1RM", "5 RM", "3rm") — the digit is required so an
    /// unrelated "RM" abbreviation elsewhere can't false-positive.
    private static let repMaxPattern = #"\b\d+\s?rm\b"#

    /// Percentage-of-max PRESCRIPTIONS ("75% 1RM", "70% of your 5RM", "80% del
    /// massimale") name a max as the load reference — that's a working set
    /// at a fraction of a known max, the opposite of a test. Stripped from
    /// the text before matching so only genuine test wording is left.
    private static let percentOfMaxPattern =
        #"\d+(?:[.,]\d+)?\s*%\s*(?:(?:of|del|dello|della|dei|di|dell['’]?)\s*)?(?:(?:your|the|il|lo|un)\s+)?(?:\d+\s?rm\b|massimal[ei]\b)"#

    /// Whole-word/phrase markers, English + Italian. Matched case-insensitive
    /// against title/notes/name/detail text combined. "test" alone is
    /// included — every example in the brief except "5RM"/"Yo-Yo" contains
    /// the literal word, and a trainer program's day/exercise text is short,
    /// domain-specific prose where "test" isn't likely to appear for any
    /// other reason.
    private static let markerPatterns: [String] = [
        #"\btest\b"#,
        #"\btime\s*trial\b"#,
        #"\byo-?\s?yo\b"#,
        #"\bmassimal[ei]\b"#, // "massimale"/"massimali" (IT: "max")
        #"\bcronometrat[ao]\b"#, // "cronometrata"/"cronometrato" (IT: timed)
        repMaxPattern,
    ]

    /// Whether ANY of `texts` (title, notes, exercise names/details — any
    /// mix, nils/empties ignored) reads as a test.
    static func isTest(_ texts: String?...) -> Bool {
        isTest(texts.compactMap(\.self))
    }

    static func isTest(_ texts: [String]) -> Bool {
        let joined = texts.filter { !$0.isEmpty }.joined(separator: " \u{2022} ")
        let combined = joined.replacingOccurrences(
            of: percentOfMaxPattern, with: " ", options: [.regularExpression, .caseInsensitive]
        )
        guard !combined.isEmpty else {
            return false
        }
        return markerPatterns.contains { pattern in
            combined.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// `ProgramDay`-level check: title + day notes only (an individual
    /// exercise's own name/detail is checked separately by
    /// `isTestExercise` — a test DAY doesn't require every block's own text
    /// to repeat the word "test").
    static func isTestDay(title: String?, notes: String?) -> Bool {
        isTest(title, notes)
    }

    /// `ProgramExercise`-level check: its own name/detail/notes.
    static func isTestExercise(name: String?, detail: String?, notes: String?) -> Bool {
        isTest(name, detail, notes)
    }
}
