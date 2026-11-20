//
// ImportedExerciseResolver.swift
// Tempo
//
// Maps an exercise name from a Strong / Hevy / generic CSV ("Bench Press
// (Barbell)", "Bent Over Row (Dumbbell)") onto the Tempo library so imported
// history lands on the SAME exercise the app already tracks instead of
// forking a custom twin with its own half of the history. Builds on
// `ExerciseMatcher` (the trainer-program matcher: aliases, shorthand,
// token overlap) and adds what CSV names need: the "(Equipment)" suffix, word
// order, and guards against confidently matching the wrong variant
// (incline vs flat, seated vs standing, dumbbell vs barbell). When nothing
// clears the bar the caller creates a custom exercise, with traits inferred
// here so it isn't dumped under "Full Body".
//

import Foundation

enum ImportedExerciseResolver {
    // MARK: - Resolve

    /// The library exercise this CSV name means, or nil when there is no
    /// confident match.
    static func resolve(_ rawName: String, in library: [ExerciseMatcher.Candidate]) -> ExerciseMatcher.Candidate? {
        let raw = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = ExerciseMatcher.normalize(raw)
        guard !normalized.isEmpty else {
            return nil
        }

        // 1. The exact name (also finds a custom exercise an earlier import made).
        if let exact = library.first(where: { ExerciseMatcher.normalize($0.name) == normalized }) {
            return exact
        }

        let (base, parenthetical) = splitEquipmentSuffix(raw)
        let writtenEquipment = ExerciseMatcher.writtenEquipment(in: parenthetical.isEmpty ? raw : parenthetical)
        let equipmentPrefixed = parenthetical.isEmpty ? base : "\(parenthetical) \(base)"
        let variants = [equipmentPrefixed, base].filter { !$0.isEmpty }

        // 2. Same words in any order / plural / shorthand ("Barbell Bench
        //    Press" == "Bench Press (Barbell)", "Triceps Pushdown").
        for variant in variants {
            let key = wordSet(variant)
            if !key.isEmpty,
               let same = library.first(where: { wordSet($0.name) == key }),
               compatible(query: raw, candidate: same.name, writtenEquipment: writtenEquipment)
            {
                return same
            }
        }

        // 3. Alias table ("Deadlift" -> Conventional Deadlift, "Pull Up" ->
        //    Pull-Up), but never onto a lift built on different equipment than
        //    the file names ("Bicep Curl (Dumbbell)" is not the barbell curl).
        for variant in variants {
            let key = ExerciseMatcher.normalize(variant)
            for query in [key, ExerciseMatcher.expandShorthand(key)] {
                if let canonical = ExerciseMatcher.aliases[query],
                   let target = library.first(where: {
                       ExerciseMatcher.normalize($0.name) == ExerciseMatcher.normalize(canonical)
                   }),
                   compatible(query: raw, candidate: target.name, writtenEquipment: writtenEquipment)
                {
                    return target
                }
            }
        }

        //    Names the trainer table doesn't know but Strong/Hevy users have.
        for variant in variants {
            let key = ExerciseMatcher.expandShorthand(ExerciseMatcher.normalize(variant))
            if let canonical = importAliases[key],
               let target = library.first(where: {
                   ExerciseMatcher.normalize($0.name) == ExerciseMatcher.normalize(canonical)
               }),
               compatible(query: raw, candidate: target.name, writtenEquipment: writtenEquipment, checkVariants: false)
            {
                return target
            }
        }

        // 4. Token-overlap fuzzy match. A bare base name is skipped when the
        //    file named equipment: the matcher's alias step would ignore it.
        let fuzzyQueries = writtenEquipment == nil ? variants : [equipmentPrefixed]
        for query in fuzzyQueries {
            if let fuzzy = ExerciseMatcher.match(query, in: library),
               compatible(query: raw, candidate: fuzzy.name, writtenEquipment: writtenEquipment)
            {
                return fuzzy
            }
        }
        return nil
    }

    /// Curated CSV spellings (post-shorthand-expansion) -> library name.
    private static let importAliases: [String: String] = [
        "bent over row": "Barbell Row",
        "barbell bent over row": "Barbell Row",
        "dumbbell row": "Single-Arm Dumbbell Row",
        "dumbbell bent over row": "Single-Arm Dumbbell Row",
        "one arm dumbbell row": "Single-Arm Dumbbell Row",
        "t bar row": "T-Bar Row",
        "lying leg curl": "Leg Curl",
        "skullcrusher": "Skull Crusher",
        "ez bar skullcrusher": "Skull Crusher",
        "ez bar skull crusher": "Skull Crusher",
        "preacher curl": "Preacher Curl",
        "reverse fly": "Dumbbell Reverse Fly",
        "dumbbell reverse fly": "Dumbbell Reverse Fly",
        "overhead press": "Overhead Press",
        "sumo deadlift": "Sumo Deadlift",
        "hammer curl": "Hammer Curl",
        "lat pulldown": "Lat Pulldown",
    ]

    /// "Bench Press (Barbell)" -> ("Bench Press", "Barbell"); several groups
    /// are joined. A name with no parentheses returns itself and "".
    static func splitEquipmentSuffix(_ raw: String) -> (base: String, parenthetical: String) {
        var base = ""
        var inside = ""
        var depth = 0
        for char in raw {
            switch char {
            case "(":
                depth += 1
            case ")":
                depth = max(0, depth - 1)
            default:
                if depth > 0 {
                    inside.append(char)
                } else {
                    base.append(char)
                }
            }
        }
        let collapse: (String) -> String = {
            $0.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return (collapse(base), collapse(inside))
    }

    private static func wordSet(_ name: String) -> Set<String> {
        let (base, parenthetical) = splitEquipmentSuffix(name)
        let expanded = ExerciseMatcher.expandShorthand(ExerciseMatcher.normalize("\(parenthetical) \(base)"))
        return Set(expanded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }

    /// Words that make a DIFFERENT lift, not just a different spelling. If one
    /// side has one the other lacks, the match is wrong.
    private static let variantWords: Set<String> = [
        "incline", "decline", "seated", "standing", "lying", "front", "close", "wide", "narrow",
        "reverse", "sumo", "romanian", "stiff", "hammer", "single", "bulgarian", "goblet", "hack",
        "assisted", "weighted", "overhead", "rear", "lateral", "preacher", "concentration", "pause",
        "deficit", "jump", "box", "kneeling", "sissy", "split", "walking", "pendlay", "supported",
    ]

    private static func compatible(
        query: String,
        candidate: String,
        writtenEquipment: Equipment?,
        checkVariants: Bool = true
    ) -> Bool {
        if let written = writtenEquipment,
           let other = ExerciseMatcher.writtenEquipment(in: candidate),
           other != written
        {
            return false
        }
        guard checkVariants else {
            return true
        }
        let q = wordSet(query).intersection(variantWords)
        let c = wordSet(candidate).intersection(variantWords)
        return q == c
    }

    // MARK: - Traits for a brand-new custom exercise

    struct Traits: Equatable {
        let muscleGroup: MuscleGroup
        let equipment: Equipment
        let movementPattern: MovementPattern
        let isCompound: Bool
    }

    /// Best-effort classification so a custom exercise lands under the right
    /// muscle group (not "Full Body") — still editable in the library.
    static func traits(for rawName: String) -> Traits {
        let (base, parenthetical) = splitEquipmentSuffix(rawName)
        let name = ExerciseMatcher.normalize("\(parenthetical) \(base)")
        let muscle = muscleGroup(for: name)
        let equipment = ExerciseMatcher.writtenEquipment(in: rawName) ?? bodyweightEquipment(for: name)
        let pattern = movementPattern(for: name, muscle: muscle)
        let isolationWords = ["curl", "fly", "flye", "raise", "extension", "kickback", "pushdown", "push down", "crunch", "shrug"]
        let compound = !isolationWords.contains(where: name.contains)
            && [.chest, .back, .quads, .hamstrings, .glutes, .shoulders].contains(muscle)
        return Traits(muscleGroup: muscle, equipment: equipment, movementPattern: pattern, isCompound: compound)
    }

    private static func bodyweightEquipment(for name: String) -> Equipment {
        let words = ["pull up", "pull-up", "pullup", "chin up", "chin-up", "push up", "push-up", "pushup", "dip", "plank",
                     "sit up", "sit-up", "crunch", "burpee", "muscle up", "leg raise"]
        return words.contains(where: name.contains) ? .bodyweight : .none
    }

    /// First matching rule wins — order encodes precedence ("leg curl" is a
    /// hamstring move before "curl" says biceps; "tricep" before "press").
    private static let muscleRules: [(MuscleGroup, [String])] = [
        (.forearms, ["wrist", "forearm", "farmer", "grip"]),
        (.calves, ["calf", "calves"]),
        (.triceps, ["tricep", "skull", "pushdown", "push down", "jm press", "kickback", "dip", "close grip bench", "close-grip bench"]),
        (.hamstrings, ["leg curl", "hamstring", "romanian", "rdl", "stiff leg", "stiff-leg", "good morning", "nordic"]),
        (.glutes, ["hip thrust", "glute", "bridge", "abduct", "pull through", "pull-through"]),
        (.quads, ["squat", "leg press", "leg extension", "lunge", "step up", "step-up", "quad", "sissy"]),
        (.biceps, ["bicep", "curl", "preacher"]),
        (.shoulders, [
            "shoulder", "overhead press", "military", "lateral raise", "front raise", "rear delt", "reverse fly",
            "face pull", "arnold", "upright row", "delt", "z press", "landmine press",
        ]),
        (.back, [
            "row", "pulldown", "pull down", "pull up", "pull-up", "pullup", "chin up", "chin-up", "lat ", "deadlift",
            "rack pull", "shrug", "pullover", "back extension", "hyperextension", "trap",
        ]),
        (.chest, ["bench", "chest", "pec", "fly", "flye", "push up", "push-up", "pushup", "crossover", "press"]),
        (.core, ["crunch", "plank", "sit up", "sit-up", "ab ", "abs", "leg raise", "twist", "woodchop", "dead bug", "rollout", "hanging"]),
        (.cardio, [
            "running", " run ", "treadmill", "bike", "cycling", "elliptical", "jump rope", "swim", "stair", " ski ", "walk", "cardio", "rowing machine",
        ]),
    ]

    private static func muscleGroup(for name: String) -> MuscleGroup {
        let padded = " \(name) "
        for (group, keys) in muscleRules where keys.contains(where: padded.contains) {
            return group
        }
        return .fullBody
    }

    private static func movementPattern(for name: String, muscle: MuscleGroup) -> MovementPattern {
        func has(_ words: String...) -> Bool {
            words.contains(where: name.contains)
        }
        if muscle == .cardio {
            return .cardio
        }
        if has("plank") {
            return .plank
        }
        if has("carry", "farmer") {
            return .carry
        }
        if has("lunge", "step up", "step-up", "split squat") {
            return .lunge
        }
        if has("squat", "leg press", "hack") {
            return .squat
        }
        if has("deadlift", "romanian", "rdl", "hip thrust", "good morning", "swing", "pull through", "pull-through") {
            return .hinge
        }
        if has("pulldown", "pull down", "pull up", "pull-up", "pullup", "chin up", "chin-up") {
            return .verticalPull
        }
        if has("row") {
            return .horizontalPull
        }
        if has("curl", "raise", "extension", "fly", "flye", "kickback", "pushdown", "push down", "crunch", "shrug") {
            return .isolation
        }
        if has("overhead", "shoulder press", "military", "z press") {
            return .verticalPush
        }
        if has("press", "bench", "push up", "push-up", "pushup", "dip") {
            return .horizontalPush
        }
        if has("twist", "woodchop") {
            return .rotation
        }
        return .isolation
    }
}
