//
// ExerciseMatcher.swift
// Tempo
//
// Matches a trainer-written exercise name ("bench", "RDL", "panca piana")
// against the library so a Trainer Program import lands on a real Exercise
// row instead of a pile of one-off customs. Pure functions — no SwiftData —
// so the matching logic is unit-testable against hand-built name lists; the
// caller (TrainerProgramSaver, or the review screen for its live indicator)
// supplies the current library as `[Candidate]`.
//

import Foundation

// MARK: - ExerciseMatcher

enum ExerciseMatcher {
    /// The only fields the matcher needs — decoupled from the `Exercise`
    /// SwiftData model so matching can be unit-tested without a ModelContext.
    struct Candidate: Hashable {
        let id: UUID
        let name: String
    }

    /// Case/diacritic-insensitive exact match, then a small English/Italian
    /// alias table, then a token-overlap fallback. Returns nil when nothing
    /// clears the fallback's confidence bar — the caller then creates a
    /// custom exercise.
    static func match(_ rawName: String, in library: [Candidate]) -> Candidate? {
        let query = normalize(rawName)
        guard !query.isEmpty else {
            return nil
        }

        if let exact = library.first(where: { normalize($0.name) == query }) {
            return exact
        }

        if let canonical = aliases[query] {
            let target = normalize(canonical)
            if let aliased = library.first(where: { normalize($0.name) == target }) {
                return aliased
            }
        }

        return tokenOverlapMatch(query, in: library)
    }

    // MARK: - Normalization

    static func normalize(_ text: String) -> String {
        text
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokens(_ normalized: String) -> Set<String> {
        Set(
            normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && !stopWords.contains($0) }
        )
    }

    private static let stopWords: Set<String> = ["the", "a", "an", "di", "da", "con", "del", "la", "il"]

    /// Best candidate whose name shares at least half of the query's
    /// meaningful tokens — enough to catch "incline dumbbell" ->
    /// "Incline Dumbbell Press" without matching unrelated exercises that
    /// happen to share one common word (e.g. "press").
    private static func tokenOverlapMatch(_ query: String, in library: [Candidate]) -> Candidate? {
        let queryTokens = tokens(query)
        guard !queryTokens.isEmpty else {
            return nil
        }

        // Short queries (<=2 meaningful tokens) are too easy to false-positive
        // on a single generic word — "band press" would otherwise share just
        // "press" with "Overhead Press" and silently match the wrong lift.
        // Require every token for a short query; longer queries can still
        // match on a majority of their tokens.
        let requiredOverlap = queryTokens.count <= 2
            ? queryTokens.count
            : Int((Double(queryTokens.count) / 2).rounded(.up))

        var best: (candidate: Candidate, score: Double)?
        for candidate in library {
            let candidateTokens = tokens(normalize(candidate.name))
            guard !candidateTokens.isEmpty else {
                continue
            }
            let overlap = queryTokens.intersection(candidateTokens).count
            guard overlap >= requiredOverlap else {
                continue
            }
            let score = Double(overlap) / Double(queryTokens.count)
            if best == nil
                || score > best!.score
                || (score == best!.score && candidate.name.count < best!.candidate.name.count)
            {
                best = (candidate, score)
            }
        }
        return best?.candidate
    }

    // MARK: - Alias table

    /// Normalized query -> canonical library name. English + Italian gym
    /// shorthand a trainer would actually write on a sheet. Not exhaustive —
    /// the token-overlap fallback covers the long tail; anything still
    /// unmatched becomes a custom exercise.
    static let aliases: [String: String] = [
        "bench": "Barbell Bench Press",
        "bench press": "Barbell Bench Press",
        "flat bench": "Barbell Bench Press",
        "panca": "Barbell Bench Press",
        "panca piana": "Barbell Bench Press",
        "incline bench": "Incline Dumbbell Press",
        "panca inclinata": "Incline Dumbbell Press",
        "ohp": "Overhead Press",
        "overhead press": "Overhead Press",
        "military press": "Overhead Press",
        "lento avanti": "Overhead Press",
        "squat": "Barbell Back Squat",
        "back squat": "Barbell Back Squat",
        "front squat": "Front Squat",
        "deadlift": "Conventional Deadlift",
        "stacchi": "Conventional Deadlift",
        "stacco": "Conventional Deadlift",
        "stacco da terra": "Conventional Deadlift",
        "rdl": "Romanian Deadlift",
        "romanian deadlift": "Romanian Deadlift",
        "stacco rumeno": "Romanian Deadlift",
        "stacco romeno": "Romanian Deadlift",
        "lat pulldown": "Lat Pulldown",
        "lat machine": "Lat Pulldown",
        "pulldown": "Lat Pulldown",
        "chest press": "Machine Chest Press",
        "pull up": "Pull-Up",
        "pull-up": "Pull-Up",
        "pullup": "Pull-Up",
        "trazioni": "Pull-Up",
        "trazioni alla sbarra": "Pull-Up",
        "chin up": "Chin-Up",
        "chin-up": "Chin-Up",
        "trazioni supine": "Chin-Up",
        "row": "Barbell Row",
        "barbell row": "Barbell Row",
        "rematore": "Barbell Row",
        "seated row": "Seated Cable Row",
        "cable row": "Seated Cable Row",
        "curl": "Barbell Curl",
        "bicep curl": "Barbell Curl",
        "curl bicipiti": "Barbell Curl",
        "hammer curl": "Hammer Curl",
        "tricep pushdown": "Tricep Pushdown",
        "pushdown": "Tricep Pushdown",
        "shoulder press": "Dumbbell Shoulder Press",
        "lateral raise": "Lateral Raise",
        "alzate laterali": "Lateral Raise",
        "calf raise": "Standing Calf Raise",
        "polpacci": "Standing Calf Raise",
        "plank": "Plank",
        "plancia": "Plank",
        "dip": "Tricep Dip",
        "dip tricipiti": "Tricep Dip",
        "push up": "Push-Up",
        "push-up": "Push-Up",
        "pushup": "Push-Up",
        "piegamenti": "Push-Up",
        "farmer's walk": "Farmer's Walk",
        "farmer walk": "Farmer's Walk",
        "farmer carry": "Farmer's Walk",
        "goblet squat": "Goblet Squat",
        "bulgarian split squat": "Bulgarian Split Squat",
        "affondi bulgari": "Bulgarian Split Squat",
        "lunge": "Walking Lunge",
        "affondi": "Walking Lunge",
        "shrug": "Barbell Shrug",
        "scrollate": "Barbell Shrug",
        "leg press": "Leg Press",
        "leg curl": "Leg Curl",
        "leg extension": "Leg Extension",
        "hip thrust": "Hip Thrust",
        "spinta anca": "Hip Thrust",
    ]
}
