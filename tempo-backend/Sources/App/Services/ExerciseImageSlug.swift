import Foundation

// MARK: - ExerciseImageSlug

//
// Deterministic slug for an exercise's generated image row (primary key of
// `exercise_images`). MUST produce byte-identical output to the iOS
// counterpart (Tempo/Tempo/Utilities/ExerciseImageSlug.swift) — the same
// exercise name has to resolve to the same slug on both sides, or the app
// will 404 against an image the backend generated under a different key.
// Keep the two algorithms and their test vectors in sync.
//
// Algorithm:
//   1. Lowercase.
//   2. Transliterate/strip diacritics (fold to plain ASCII where possible).
//   3. Any run of characters outside [a-z0-9] collapses to a single "-".
//   4. Trim leading/trailing "-".

enum ExerciseImageSlug {
    static func make(from rawName: String) -> String {
        let folded = rawName
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        var slug = ""
        var pendingSeparator = false

        for scalar in folded.unicodeScalars {
            if ("a" ... "z").contains(scalar) || ("0" ... "9").contains(scalar) {
                if pendingSeparator, !slug.isEmpty {
                    slug.append("-")
                }
                slug.unicodeScalars.append(scalar)
                pendingSeparator = false
            } else {
                pendingSeparator = true
            }
        }

        return slug
    }
}
