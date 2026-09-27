//
// VoicePantryEditIntent.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation

// MARK: - PantryEditIntent

/// One parsed clause from a voice-edit transcript. Deliberately a pure,
/// offline, rule-based parser (NOT another Haiku round-trip like
/// `VoicePantryService`'s add/set flow) — the original voice-pantry design
/// doc explicitly deferred "voice-driven pantry EDIT/REMOVE" as a later
/// tier, and these five phrasings are regular enough that a network call
/// would just add latency and cost for no accuracy gain. Also means these
/// intents are fully unit-testable with zero mocking.
enum PantryEditIntent: Equatable, Sendable {
    /// "I'm out of rice" — the user is reporting a food is gone, whether or
    /// not the pantry has a tracked row for it. Zeroes any matching row(s)
    /// AND unconditionally queues a grocery-list add (an explicit "I'm out"
    /// is a restock request, unlike an incidental decrement depletion).
    case markDepleted(rawName: String)

    /// "I used the chicken" (fraction 1.0) / "I used half the rice"
    /// (fraction 0.5). Reduces matching row(s) by `fraction` of their
    /// current quantity, FIFO across brand duplicates.
    case decrement(rawName: String, fraction: Double)

    /// "move the chicken to the freezer" — location change, recomputes
    /// useBy the same way the tap-edit sheet does.
    case move(rawName: String, location: PantryStorageLocation)

    /// "throw out the spinach" — archived as waste. No grocery-list side
    /// effect (an accidental spoilage isn't necessarily a "buy again").
    case discard(rawName: String)
}

// MARK: - VoicePantryEditParser

enum VoicePantryEditParser {
    /// Splits a transcript into clauses ("move the chicken to the freezer
    /// and I'm out of rice") and parses each independently. Unrecognized
    /// clauses are dropped — callers show the recognized list for
    /// confirmation before applying, so a silently-dropped clause is safer
    /// than a wrong guess.
    static func parse(_ transcript: String) -> [PantryEditIntent] {
        let clauses = splitClauses(transcript)
        return clauses.compactMap(parseClause)
    }

    private static func splitClauses(_ transcript: String) -> [String] {
        transcript
            .replacingOccurrences(of: " and also ", with: "; ", options: .caseInsensitive)
            .replacingOccurrences(of: ", and ", with: "; ", options: .caseInsensitive)
            .replacingOccurrences(of: " and ", with: "; ", options: .caseInsensitive)
            .components(separatedBy: CharacterSet(charactersIn: ";.\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static let locationKeywords: [String: PantryStorageLocation] = [
        "fridge": .fridge,
        "refrigerator": .fridge,
        "freezer": .freezer,
        "pantry": .pantry,
        "cupboard": .cupboard,
        "cabinet": .cupboard,
        "counter": .cupboard,
    ]

    private static func parseClause(_ raw: String) -> PantryEditIntent? {
        let clause = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !clause.isEmpty else {
            return nil
        }

        // "I'm out of X" / "we're out of X" / "out of X" / "no more X"
        for prefix in ["i'm out of ", "im out of ", "we're out of ", "were out of ", "out of ", "no more "] {
            if clause.hasPrefix(prefix) {
                let name = clean(String(clause.dropFirst(prefix.count)))
                guard !name.isEmpty else {
                    return nil
                }
                return .markDepleted(rawName: name)
            }
        }

        // "throw out the X" / "toss the X" / "discard the X" / "throw away the X"
        for prefix in ["throw out ", "throw away ", "toss out ", "toss ", "discard "] {
            if clause.hasPrefix(prefix) {
                let name = clean(String(clause.dropFirst(prefix.count)))
                guard !name.isEmpty else {
                    return nil
                }
                return .discard(rawName: name)
            }
        }

        // "move the X to the freezer" / "put the X in the fridge"
        for prefix in ["move ", "put "] {
            if clause.hasPrefix(prefix) {
                let rest = String(clause.dropFirst(prefix.count))
                guard let (name, location) = splitOnLocation(rest) else {
                    continue
                }
                guard !name.isEmpty else {
                    return nil
                }
                return .move(rawName: name, location: location)
            }
        }

        // "I used half the X" / "I used half of the X" / "half the X"
        for prefix in ["i used half of the ", "i used half of ", "i used half the ", "i used half ", "half the ", "half of the "] {
            if clause.hasPrefix(prefix) {
                let name = clean(String(clause.dropFirst(prefix.count)))
                guard !name.isEmpty else {
                    return nil
                }
                return .decrement(rawName: name, fraction: 0.5)
            }
        }

        // "I used the X" / "I used up the X" / "I used all the X" / "used the X"
        for prefix in ["i used up ", "i used all of the ", "i used all the ", "i used ", "used up ", "used "] {
            if clause.hasPrefix(prefix) {
                let name = clean(String(clause.dropFirst(prefix.count)))
                guard !name.isEmpty else {
                    return nil
                }
                return .decrement(rawName: name, fraction: 1.0)
            }
        }

        return nil
    }

    /// Splits "the chicken to the freezer" into ("chicken", .freezer).
    private static func splitOnLocation(_ text: String) -> (String, PantryStorageLocation)? {
        for (keyword, location) in locationKeywords {
            for connector in [" to the \(keyword)", " to \(keyword)", " in the \(keyword)", " in \(keyword)"] {
                if text.hasSuffix(connector) {
                    let name = clean(String(text.dropLast(connector.count)))
                    return (name, location)
                }
            }
        }
        return nil
    }

    /// Strips leading articles/possessives ("the", "my", "some") left over
    /// after a prefix match.
    private static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        for article in ["the ", "my ", "some ", "our ", "all the ", "all of the "] {
            if result.hasPrefix(article) {
                result = String(result.dropFirst(article.count))
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
