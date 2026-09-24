import Foundation

// MARK: - ProgramImportPageSplitter

//
// Pure text splitter for the Trainer Program TRANSCRIBE step. iOS sends one
// Claude call with several image blocks and instructs the model to prefix
// each page's transcription with a sentinel line ("=== PAGE n ===") — this
// splits the raw completion back into one string per page, in the order the
// model emitted them (which matches the order the images were sent, since
// the prompt asks for that explicitly).
//
// No network, no Vapor dependency — trivially unit-testable.

enum ProgramImportPageSplitter {
    /// Splits `raw` on sentinel lines. Content before the first sentinel is
    /// discarded (preamble/chatter the model wasn't asked for). If no
    /// sentinel is found at all, the whole trimmed text is returned as a
    /// single-element array (defensive fallback for a 1-image batch where
    /// the model omitted the marker) — unless it's empty, which returns [].
    static func split(_ raw: String) -> [String] {
        // Matches a standalone sentinel line such as "=== PAGE 3 ===",
        // "==PAGE 1==", or "=== page 12 ===" (case-insensitive, flexible
        // equals-sign run length, optional surrounding whitespace). Built
        // fresh per call (not a stored static) — `Regex` isn't `Sendable`,
        // so a static-let would be a concurrency-unsafe shared global under
        // Swift 6 strict concurrency; construction is cheap.
        let sentinelPattern = #/(?im)^[ \t]*=+[ \t]*PAGE[ \t]+\d+[ \t]*=+[ \t]*$/#
        let ranges = raw.ranges(of: sentinelPattern)
        guard !ranges.isEmpty else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }

        var pages: [String] = []
        for (index, range) in ranges.enumerated() {
            let contentStart = range.upperBound
            let contentEnd = index + 1 < ranges.count ? ranges[index + 1].lowerBound : raw.endIndex
            guard contentStart <= contentEnd else {
                pages.append("")
                continue
            }
            let content = String(raw[contentStart ..< contentEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            pages.append(content)
        }
        return pages
    }
}
