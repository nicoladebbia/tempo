//
// ConditioningTargetParser.swift
// Tempo
//
// Trainer-written conditioning prescriptions are free text (ProgramExercise
// .detail) — "4 reps of 25y out and back in < 65\"", "35' (2' slow - 1' fast
// - 30\" walk + juggling)", "2 x 10times (5R-5L) 10m+5m". This turns that
// text into a structured target Fix #7's logging UI and target-met check can
// act on, without ever requiring the trainer to write anything differently.
//
// Pure and side-effect free by design — heavily unit-tested in
// ConditioningTargetParserTests. Never throws: any string that doesn't match
// a known shape becomes `.freeform`, which the UI renders as free notes with
// no target-met check.
//

import Foundation

// MARK: - ConditioningDistanceUnit

enum ConditioningDistanceUnit: String, Codable, Equatable {
    case yards
    case meters
    case kilometers

    /// This distance expressed in meters.
    func meters(_ value: Double) -> Double {
        switch self {
        case .yards: value * 0.9144
        case .meters: value
        case .kilometers: value * 1000
        }
    }

    var shortLabel: String {
        switch self {
        case .yards: "y"
        case .meters: "m"
        case .kilometers: "km"
        }
    }
}

// MARK: - ConditioningTargetKind

enum ConditioningTargetKind: Equatable {
    /// "4 reps of 25y out and back in < 65\"" — a fixed number of reps over a
    /// distance, each capped at a time. `capSeconds` is nil when a rep/distance
    /// count was found but no cap ("4 reps of 25y").
    case repsDistance(reps: Int, distance: Double, unit: ConditioningDistanceUnit, capSeconds: Double?)
    /// "35'", "15' easy", "10 min" — a straight time-on-the-clock prescription.
    case duration(minutes: Double)
    /// "2 x 10times (5R-5L) 10m+5m" — sets × reps intervals/drills.
    case intervalSets(sets: Int, reps: Int)
    /// "5 km", "800m", "300y" — a straight distance with no rep/time shape.
    case distance(value: Double, unit: ConditioningDistanceUnit)
    /// Anything that doesn't match a known shape — shown verbatim, no
    /// target-met check.
    case freeform
}

// MARK: - ConditioningTarget

struct ConditioningTarget: Equatable {
    let kind: ConditioningTargetKind
    /// The original `detail` text, kept for display alongside the parsed shape.
    let rawText: String
}

// MARK: - ConditioningTargetParser

enum ConditioningTargetParser {
    /// Parse a trainer's free-text conditioning prescription into a
    /// structured target. Never fails — an unrecognized or empty string
    /// returns `.freeform`.
    static func parse(detail: String?) -> ConditioningTarget {
        let raw = (detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return ConditioningTarget(kind: .freeform, rawText: raw)
        }
        let lower = raw.lowercased()

        if let kind = parseRepsDistance(lower) {
            return ConditioningTarget(kind: kind, rawText: raw)
        }
        if let kind = parseIntervalSets(lower) {
            return ConditioningTarget(kind: kind, rawText: raw)
        }
        if let kind = parseDuration(lower) {
            return ConditioningTarget(kind: kind, rawText: raw)
        }
        if let kind = parseDistance(lower) {
            return ConditioningTarget(kind: kind, rawText: raw)
        }
        return ConditioningTarget(kind: .freeform, rawText: raw)
    }

    // MARK: - reps × distance (+ optional cap)

    /// "4 reps of 25y out and back in < 65\"", "4 ripetute da 25y in < 65\""
    private static func parseRepsDistance(_ text: String) -> ConditioningTargetKind? {
        guard let repsMatch = firstMatch(
            in: text,
            pattern: #"(\d+)\s*(?:reps?|ripetute|volte)\b"#
        )
        else {
            return nil
        }
        guard let reps = Int(repsMatch.groups[1] ?? "") else {
            return nil
        }
        // Distance number+unit anywhere AFTER the reps count.
        let tail = String(text[repsMatch.range.upperBound...])
        guard let distMatch = firstMatch(in: tail, pattern: distanceNumberUnitPattern),
              let distanceValue = parseDouble(distMatch.groups[1]),
              let unit = unit(from: distMatch.groups[2])
        else {
            return nil
        }
        let capSeconds = parseCapSeconds(text)
        return .repsDistance(reps: reps, distance: distanceValue, unit: unit, capSeconds: capSeconds)
    }

    /// A "< 65\"" / "≤ 65 sec" / "< 65 secondi" style cap, searched anywhere
    /// in the string (it usually trails the distance clause).
    private static func parseCapSeconds(_ text: String) -> Double? {
        guard let match = firstMatch(
            in: text,
            pattern: #"[<≤]\s*(\d+(?:[.,]\d+)?)\s*(?:"|”|''|sec\.?|secondi|seconds?)"#
        )
        else {
            return nil
        }
        return parseDouble(match.groups[1])
    }

    // MARK: - interval sets

    /// "2 x 10times (5R-5L) 10m+5m", "3x8", "4 X 6 reps"
    private static func parseIntervalSets(_ text: String) -> ConditioningTargetKind? {
        guard let match = firstMatch(
            in: text,
            pattern: #"(\d+)\s*[x×]\s*(\d+)\s*(?:times|reps?|x)?"#
        )
        else {
            return nil
        }
        guard let sets = Int(match.groups[1] ?? ""), let reps = Int(match.groups[2] ?? "") else {
            return nil
        }
        return .intervalSets(sets: sets, reps: reps)
    }

    // MARK: - duration

    /// "35'", "15' easy", "10 min", "10 minuti". Takes the FIRST duration
    /// marker in the string — a parenthetical breakdown ("2' slow - 1' fast")
    /// describes the same block, not a second target.
    private static func parseDuration(_ text: String) -> ConditioningTargetKind? {
        // Two separate patterns, tried independently and merged on whichever
        // starts first: `\b` after a word-like unit (min/minuti/minutes)
        // correctly requires a word→non-word transition, but the SAME `\b`
        // after the apostrophe/prime marker never fires — a digit-quote is
        // followed by a space or `(`, and neither side of THAT boundary is a
        // word character, so `\b` has nothing to transition across. Keeping
        // the apostrophe/prime match unanchored avoids silently dropping
        // "35'", "15'", etc.
        let apostrophe = firstMatch(in: text, pattern: #"(\d+(?:[.,]\d+)?)\s*[′']"#)
        let worded = firstMatch(in: text, pattern: #"(\d+(?:[.,]\d+)?)\s*(?:min\.?|minuti|minutes?)\b"#)
        let match = [apostrophe, worded].compactMap(\.self).min { $0.range.lowerBound < $1.range.lowerBound }
        guard let match, let minutes = parseDouble(match.groups[1]) else {
            return nil
        }
        return .duration(minutes: minutes)
    }

    // MARK: - distance only

    /// "5 km", "800m", "300y" — no reps/duration wording found first.
    private static func parseDistance(_ text: String) -> ConditioningTargetKind? {
        guard let match = firstMatch(in: text, pattern: distanceNumberUnitPattern),
              let value = parseDouble(match.groups[1]),
              let unit = unit(from: match.groups[2])
        else {
            return nil
        }
        return .distance(value: value, unit: unit)
    }

    // MARK: - Shared helpers

    /// Number immediately followed by a distance unit. Longest-alternative
    /// first isn't required — `\b` after the unit rejects a partial match
    /// (e.g. "m" can't match inside "min" because 'm' + 'i' isn't a boundary).
    private static let distanceNumberUnitPattern =
        #"(\d+(?:[.,]\d+)?)\s*(km|chilometri|kilometers?|yards?|yd|y|meters?|metri|mt|m)\b"#

    private static func unit(from raw: String?) -> ConditioningDistanceUnit? {
        switch raw {
        case "y",
             "yd",
             "yard",
             "yards":
            .yards
        case "m",
             "mt",
             "meter",
             "meters",
             "metro",
             "metri":
            .meters
        case "km",
             "kilometer",
             "kilometers",
             "chilometro",
             "chilometri":
            .kilometers
        default:
            nil
        }
    }

    private static func parseDouble(_ raw: String?) -> Double? {
        guard let raw else {
            return nil
        }
        return Double(raw.replacingOccurrences(of: ",", with: "."))
    }

    private struct RegexMatch {
        let range: Range<String.Index>
        /// 1-based capture groups (group 0 is the whole match, unused here).
        let groups: [Int: String]
    }

    private static func firstMatch(in text: String, pattern: String) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, options: [], range: nsRange) else {
            return nil
        }
        guard let fullRange = Range(result.range, in: text) else {
            return nil
        }
        var groups: [Int: String] = [:]
        for i in 1 ..< result.numberOfRanges {
            let r = result.range(at: i)
            if r.location != NSNotFound, let swiftRange = Range(r, in: text) {
                groups[i] = String(text[swiftRange])
            }
        }
        return RegexMatch(range: fullRange, groups: groups)
    }
}
