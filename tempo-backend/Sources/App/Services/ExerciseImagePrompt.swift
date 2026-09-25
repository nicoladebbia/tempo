import Foundation

// MARK: - ExerciseImagePrompt

//
// One fixed, deterministic prompt template so every generated exercise
// picture matches the same visual style (clean 3D-rendered fitness
// illustration, dark neutral studio, primary muscles highlighted in red).
// Deterministic on purpose: same inputs -> byte-identical prompt, so
// re-running the CLI backfill against an already-generated slug is a no-op
// (idempotency lives on the slug, but a stable prompt also makes the
// generated `prompt` column diffable/auditable).

enum ExerciseImagePrompt {
    static func build(
        name: String,
        equipment: String,
        muscleGroup: String,
        movementPattern: String? = nil,
        instructions: String? = nil
    ) -> String {
        let equipmentPhrase = equipmentPhrase(for: equipment)
        let musclePhrase = humanize(muscleGroup)

        var sentence = """
        Clean high-detail 3D-rendered fitness illustration, an athletic person \
        performing \(name) with \(equipmentPhrase), side view showing the start \
        and end position of the movement, primary muscles (\(musclePhrase)) \
        subtly highlighted in red, dark neutral studio background, soft rim \
        lighting, no text, no logos, no watermark.
        """

        if let pattern = movementPattern, !pattern.isEmpty {
            sentence += " Movement pattern: \(humanize(pattern))."
        }

        if let disambiguation = disambiguation(from: instructions) {
            sentence += " Movement detail: \(disambiguation)."
        }

        return sentence
    }

    // MARK: - Helpers

    private static func equipmentPhrase(for equipment: String) -> String {
        let normalized = equipment.lowercased()
        if normalized.isEmpty || normalized == "none" || normalized == "bodyweight" {
            return "no equipment (bodyweight only)"
        }
        return humanize(equipment)
    }

    /// First non-empty instruction line, trimmed of leading numbering
    /// ("1. Lie on the bench..." -> "Lie on the bench..."), used to
    /// disambiguate movements that share a name/equipment/muscle group
    /// (e.g. "Barbell Row" variants).
    private static func disambiguation(from instructions: String?) -> String? {
        guard let instructions, !instructions.isEmpty else { return nil }
        guard let firstLine = instructions
            .split(whereSeparator: \.isNewline)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else {
            return nil
        }
        var line = firstLine.trimmingCharacters(in: .whitespaces)
        // Strip a leading "1. " / "1) " ordinal, if present.
        if let dotRange = line.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) {
            line.removeSubrange(dotRange)
        }
        return line.isEmpty ? nil : line
    }

    private static func humanize(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
