//
// GuidedRunRestParser.swift
// Tempo
//
// Guided run mode — the trainer's rest between reps/rounds, mined from a
// conditioning block's free-text `detail` when the structured
// `ProgramExercise.restSeconds` field is absent: "rest 60\"", "1' rec",
// Italian "rec"/"recupero" too, either order ("rec 1'30\"", "90\" recupero").
// Pure and side-effect free, mirroring ConditioningTargetParser's style —
// never throws, returns nil when nothing rest-shaped is found so the caller
// falls back to its own default.
//

import Foundation

enum GuidedRunRestParser {
    static func parseSeconds(_ text: String?) -> Double? {
        guard let text, !text.isEmpty else {
            return nil
        }
        let lower = text.lowercased()
        let keyword = #"(?:rest|rec\.?|recupero)"#
        let secondsMarker = #"(?:"|”|''|sec\.?|secondi|seconds?)"#

        // "rec 1'30\"", "rest 1' 30\"" — keyword then a COMBINED minutes'
        // + seconds" — tried first since it's the most specific shape; a
        // bare minutes-only pattern below would otherwise match just the
        // "1'" and silently drop the trailing "30\"".
        if let match = firstMatch(
            in: lower,
            pattern: keyword + #"\s*:?\s*(\d+)\s*[′']\s*(\d+(?:[.,]\d+)?)\s*"# + secondsMarker
        ), let minutes = parseDouble(match.groups[1]), let seconds = parseDouble(match.groups[2]) {
            return minutes * 60 + seconds
        }
        // "1'30\" rec", "1' 30\" recupero" — COMBINED minutes'+seconds"
        // then keyword.
        if let match = firstMatch(
            in: lower,
            pattern: #"(\d+)\s*[′']\s*(\d+(?:[.,]\d+)?)\s*"# + secondsMarker + #"\s*"# + keyword
        ), let minutes = parseDouble(match.groups[1]), let seconds = parseDouble(match.groups[2]) {
            return minutes * 60 + seconds
        }
        // "rest 60\"", "rec 90 sec", "recupero 45 secondi" — keyword then a
        // seconds-marked number.
        if let match = firstMatch(
            in: lower,
            pattern: keyword + #"\s*:?\s*(\d+(?:[.,]\d+)?)\s*"# + secondsMarker
        ), let seconds = parseDouble(match.groups[1]) {
            return seconds
        }
        // "60\" rest", "90 sec rec" — seconds-marked number then keyword.
        if let match = firstMatch(
            in: lower,
            pattern: #"(\d+(?:[.,]\d+)?)\s*(?:"|”|''|sec\.?|secondi|seconds?)\s*"# + keyword
        ), let seconds = parseDouble(match.groups[1]) {
            return seconds
        }
        // "rest 1'" — keyword then a bare minute-marked number (no
        // trailing seconds — that combined shape is handled above).
        if let match = firstMatch(
            in: lower,
            pattern: keyword + #"\s*:?\s*(\d+(?:[.,]\d+)?)\s*[′']"#
        ), let minutes = parseDouble(match.groups[1]) {
            return minutes * 60
        }
        // "1' rec", "1' recupero" — minute-marked number then keyword.
        if let match = firstMatch(
            in: lower,
            pattern: #"(\d+(?:[.,]\d+)?)\s*[′']\s*"# + keyword
        ), let minutes = parseDouble(match.groups[1]) {
            return minutes * 60
        }
        return nil
    }

    // MARK: - Shared regex helper (mirrors ConditioningTargetParser)

    private struct RegexMatch {
        let range: Range<String.Index>
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

    private static func parseDouble(_ raw: String?) -> Double? {
        guard let raw else {
            return nil
        }
        return Double(raw.replacingOccurrences(of: ",", with: "."))
    }
}
