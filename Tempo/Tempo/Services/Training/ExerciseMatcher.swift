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

        // Trainer shorthand ("SA DB OH Tricep Extension", "KT SL RDL"):
        // expand abbreviations, then retry exact/alias before the fuzzy pass.
        let expanded = expandShorthand(query)
        if expanded != query {
            if let exact = library.first(where: { normalize($0.name) == expanded }) {
                return exact
            }
            if let canonical = aliases[expanded],
               let aliased = library.first(where: { normalize($0.name) == normalize(canonical) })
            {
                return aliased
            }
        }

        return tokenOverlapMatch(expanded, in: library)
    }

    // MARK: - Shorthand

    /// Abbreviations trainers write on sheets → words the library uses.
    static let shorthand: [String: String] = [
        "sa": "single arm", "sl": "single leg", "db": "dumbbell", "dbs": "dumbbell",
        "kb": "kettlebell", "kt": "kettlebell", "bb": "barbell", "oh": "overhead",
        "ohp": "overhead press", "rdl": "romanian deadlift", "lat": "lateral",
        "ext": "extension", "iso": "isometric", "bw": "bodyweight",
        "manubri": "dumbbell", "manubrio": "dumbbell", "bilanciere": "barbell",
    ]

    /// Expands shorthand tokens and singularizes simple plurals ("raises").
    /// "lat" stays "lat" before pulldown/pull-down (lat pulldown).
    static func expandShorthand(_ normalized: String) -> String {
        let words = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        var out: [String] = []
        for (index, word) in words.enumerated() {
            let next = index + 1 < words.count ? words[index + 1] : ""
            if word == "lat", next.hasPrefix("pull") || next == "machine" {
                out.append(word)
            } else if let expansion = shorthand[word] {
                out.append(expansion)
            } else {
                out.append(singular(word))
            }
        }
        return out.joined(separator: " ")
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 4, word.hasSuffix("s"), !word.hasSuffix("ss") else {
            return word
        }
        return String(word.dropLast())
    }

    /// Words that qualify HOW a lift is done (side, equipment, holds) rather
    /// than WHICH lift it is. They don't count toward the required overlap —
    /// "single arm dumbbell row" is a row — but they break ties, so a
    /// dumbbell shoulder press prefers "Dumbbell Shoulder Press" over the
    /// machine version.
    private static let modifierTokens: Set<String> = [
        "single", "arm", "leg", "unilateral", "alternating", "standing", "seated",
        "kneeling", "half", "isometric", "hold", "ball", "squeeze", "bicep", "tempo",
        "pause", "paused", "light", "heavy", "on", "position",
    ]
    private static let equipmentTokens: Set<String> = [
        "dumbbell", "barbell", "kettlebell", "cable", "machine", "smith", "band", "bodyweight", "ez", "trap",
    ]

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
        let movementTokens = queryTokens.subtracting(modifierTokens).subtracting(equipmentTokens)
        guard !movementTokens.isEmpty else {
            return nil
        }
        let queryEquipment = queryTokens.intersection(equipmentTokens)

        // Short movement descriptions (<=2 words) must match fully — "band
        // press" sharing only "press" with "Overhead Press" is not a match;
        // longer ones can match on a majority of their movement words.
        let requiredOverlap = movementTokens.count <= 2
            ? movementTokens.count
            : Int((Double(movementTokens.count) / 2).rounded(.up))

        var best: (candidate: Candidate, score: Double)?
        for candidate in library {
            let candidateTokens = tokens(expandShorthand(normalize(candidate.name)))
            guard !candidateTokens.isEmpty else {
                continue
            }
            let movementOverlap = movementTokens.intersection(candidateTokens).count
            guard movementOverlap >= requiredOverlap else {
                continue
            }
            // Movement words dominate; shared qualifiers add a little; a
            // candidate built on DIFFERENT equipment than the trainer wrote
            // (machine vs dumbbell) is penalized; extra unrelated words in the
            // candidate cost a little.
            let candidateEquipment = candidateTokens.intersection(equipmentTokens)
            // A one-word movement ("row", "press") is too generic on its own:
            // when the trainer named the equipment, the candidate must use it
            // ("band press" is not "Overhead Press"; "SA DB row" is the
            // dumbbell row).
            if movementTokens.count == 1, !queryEquipment.isEmpty,
               queryEquipment.isDisjoint(with: candidateEquipment)
            {
                continue
            }
            let equipmentConflict = !queryEquipment.isEmpty && !candidateEquipment.isEmpty
                && queryEquipment.isDisjoint(with: candidateEquipment)
            let sharedAll = queryTokens.intersection(candidateTokens).count
            let extra = candidateTokens.subtracting(queryTokens).count
            let score = Double(movementOverlap) * 3
                + Double(sharedAll - movementOverlap)
                - (equipmentConflict ? 2 : 0)
                - Double(extra) * 0.5
            if best == nil || score > best!.score
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
