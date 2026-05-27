//
// CoachMessageRenderer.swift
// Tempo
//
// Coach v2.1 Phase 7b — pure helpers for rendering chat messages.
//
// Separated from the SwiftUI view so they can be unit-tested directly.
// The view holds presentation; this enum holds presentation-adjacent
// text transforms.
//

import Foundation

enum CoachMessageRenderer {
    /// Removes any inline `[pref_<hex>]` citation markers from an
    /// assistant text body so the chat bubble reads cleanly. Citations
    /// will be re-rendered as tappable chips below the bubble (Phase 7c
    /// wiring against `LearnedPreference` lookups).
    ///
    /// Matches up to 8 hex chars after `pref_` — covers the
    /// `id.uuidString.prefix(4)` shape used in the assembler today and
    /// leaves headroom for longer prefixes if we widen later.
    static func strippingCitationMarkers(_ text: String) -> String {
        let pattern = #"\s*\[pref_[a-f0-9]{1,8}\]"#
        return text.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
    }

    /// Extracts all `[pref_<id>]` markers from a body, returning the
    /// list of short IDs the assistant cited. Phase 7c uses this to
    /// look up the corresponding `LearnedPreference` rows for the
    /// citation-chip strip.
    static func citedPreferenceShortIDs(in text: String) -> [String] {
        let pattern = #"\[pref_([a-f0-9]{1,8})\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard match.numberOfRanges >= 2,
                  let captured = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[captured])
        }
    }
}
