//
// ReceiptMultiPhotoStitcher.swift
// Tempo
//
// Round 2 item 4 — multi-photo capture for receipts too long for one frame.
// Each photo is OCR'd independently (VisionReceiptOCR has no notion of
// "this is page 2 of the same receipt"), so this file's only job is to
// stitch the per-photo row streams back into one reading-order stream and
// drop rows that are a near-duplicate re-read of the same physical line at
// the seam between two consecutive shots. Capture UI asks the user to
// overlap shots slightly (a few lines of repeated content) specifically so
// this dedup pass has something to match against — a hard cut with zero
// overlap risks silently dropping a line instead.
//

import Foundation

// MARK: - ReceiptMultiPhotoStitcher

enum ReceiptMultiPhotoStitcher {
    /// One photo's independent OCR pass, ready to be stitched.
    struct PageOCR: Sendable {
        let rows: [VisionReceiptOCRResult.Row]
        let averageConfidence: Double
    }

    struct StitchResult: Sendable {
        /// Combined rows in reading order across all pages, with seam
        /// duplicates removed. Feeds straight into `ReceiptPreParser.parse`.
        let rows: [VisionReceiptOCRResult.Row]
        /// `rows` joined back into the same wide-gap-column text format
        /// `VisionReceiptOCRResult.rawText` uses, for the structuring prompt.
        let rawText: String
        /// Row-count-weighted average across the pages that contributed.
        let averageConfidence: Double
    }

    /// Only rows within this many positions of a seam are checked against
    /// each other — keeps the comparison cheap (O(pages × window²)) and
    /// avoids a false-positive drop between two genuinely different rows
    /// that just happen to read similarly far apart on a long receipt (e.g.
    /// two separate "SAVINGS" lines in different departments).
    private static let seamWindow = 10

    /// Bigram similarity at/above which two rows are treated as the same
    /// physical line re-read on both shots. Slightly higher than the 0.5
    /// used for same-photo double-readings (`ReceiptPreParser`'s own dedup)
    /// since two independent photos/lighting conditions of the truly same
    /// line still usually OCR near-identically, whereas we want to be more
    /// conservative about ever throwing away a real second line here.
    private static let seamSimilarityThreshold = 0.6

    static func stitch(_ pages: [PageOCR]) -> StitchResult {
        guard let first = pages.first else {
            return StitchResult(rows: [], rawText: "", averageConfidence: 0)
        }
        guard pages.count > 1 else {
            return StitchResult(
                rows: first.rows,
                rawText: first.rows.map(\.text).joined(separator: "\n"),
                averageConfidence: first.averageConfidence
            )
        }

        var combined: [VisionReceiptOCRResult.Row] = first.rows
        for page in pages.dropFirst() {
            let tailStart = max(0, combined.count - seamWindow)
            let tail = combined[tailStart...]
            var kept: [VisionReceiptOCRResult.Row] = []
            for (index, row) in page.rows.enumerated() {
                // Only the head of this page can possibly be a repeat of the
                // previous page's tail — once we're past the seam window
                // every row is new content, keep it unconditionally.
                guard index < seamWindow else {
                    kept.append(row)
                    continue
                }
                let isSeamDuplicate = tail.contains {
                    ReceiptPreParser.letterBigramSimilarity($0.text, row.text) >= seamSimilarityThreshold
                }
                guard !isSeamDuplicate else {
                    continue
                }
                kept.append(row)
            }
            combined.append(contentsOf: kept)
        }

        let rawText = combined.map(\.text).joined(separator: "\n")
        let weightedTotal = pages.reduce(0.0) { $0 + $1.averageConfidence * Double($1.rows.count) }
        let totalRows = pages.reduce(0) { $0 + $1.rows.count }
        let averageConfidence = totalRows > 0 ? weightedTotal / Double(totalRows) : 0

        return StitchResult(rows: combined, rawText: rawText, averageConfidence: averageConfidence)
    }
}
