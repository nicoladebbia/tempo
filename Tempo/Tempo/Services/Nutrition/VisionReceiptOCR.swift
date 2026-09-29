//
// VisionReceiptOCR.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import CoreImage
import Foundation
import os
import UIKit
import Vision

// MARK: - VisionReceiptOCRError

enum VisionReceiptOCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed(String)
    case noTextFound
    /// Post-OCR quality gate: too few lines / too low confidence to be a
    /// usable receipt photo even after the contrast-retry pass. Distinct from
    /// `.noTextFound` (zero lines) so the UI can offer a specific retake tip.
    case tooLowQuality(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Could not read the receipt photo."
        case let .recognitionFailed(detail): "Vision recognition failed: \(detail)"
        case .noTextFound: "No text was detected on this photo."
        case let .tooLowQuality(hint): hint
        }
    }
}

// MARK: - VisionReceiptOCRResult

struct VisionReceiptOCRResult: Sendable {
    /// All text in row-reconstructed reading order, joined with newlines.
    /// Each row's columns (e.g. item name + price) are joined with enough
    /// whitespace to preserve the visual column gap for the structuring
    /// prompt. This is what gets sent to the backend as `raw_text`.
    let rawText: String

    /// Row-reconstructed structure: one entry per detected visual row, with
    /// its individual column texts left-to-right. This is what
    /// ReceiptPreParser consumes — far more reliable than re-splitting
    /// `rawText` with regex, since column boundaries are already known from
    /// Vision's bounding boxes rather than guessed from whitespace.
    let rows: [Row]

    /// Flat per-observation lines (pre-row-grouping), kept for callers that
    /// only need raw OCR lines / confidence-weighted re-parsing.
    let lines: [Line]

    /// Average confidence across all recognized text observations (0.0–1.0).
    let averageConfidence: Double

    /// The CGImagePropertyOrientation (raw value) that produced the winning
    /// pass — diagnostic only, surfaced in logs.
    let orientationUsed: Int32

    /// True if a contrast/grayscale-enhanced retry pass was needed to reach
    /// an acceptable quality bar (faded thermal print, glare, low light).
    let usedEnhancedRetry: Bool

    struct Row: Sendable {
        /// Column texts, left-to-right, as detected on this visual row.
        let columns: [String]
        /// Convenience: columns joined with a wide gap, e.g. "Bananas   1.46".
        var text: String {
            columns.joined(separator: "    ")
        }

        /// Normalized y (Vision coordinate space, origin bottom-left; 1.0 =
        /// top of the page). Rows are already sorted top-to-bottom by this.
        let yPosition: Double
        let confidence: Double
    }

    struct Line: Sendable {
        let text: String
        let confidence: Double
    }
}

// MARK: - VisionReceiptOCR

enum VisionReceiptOCR {
    private static let logger = Logger.nutrition

    /// Longest edge to downsample to before OCR. Vision's `.accurate` level
    /// doesn't need the full 12MP+ sensor image — testing against real 5712×
    /// 4284 receipt photos showed a ~2600px-long-edge downsample produces
    /// EQUAL OR MORE detected text lines than full resolution (denser text
    /// gets a better relative feature scale) while running several times
    /// faster, which matters here because orientation detection runs the
    /// recognizer up to 4x per photo.
    private static let maxOCRDimension: CGFloat = 2600

    /// Recognize text in a receipt photo. Three problems solved beyond a
    /// single `VNRecognizeTextRequest` call:
    ///
    /// 1. ORIENTATION. The old implementation called
    ///    `VNImageRequestHandler(cgImage:options:)` with NO orientation,
    ///    which defaults to `.up` — i.e. Vision read the raw sensor buffer
    ///    as-is. For a normal portrait photo (EXIF orientation 6, the common
    ///    case for anyone holding the phone vertically) the raw buffer is
    ///    actually rotated 90°. Empirically Vision's recognizer is fairly
    ///    rotation-tolerant for individual text detection, BUT the narrow
    ///    price column on a receipt (small numbers, tight line spacing)
    ///    frequently mis-segments on the wrong orientation and merges
    ///    several rows' prices into one garbled observation — verified
    ///    against 3 real Publix receipts: the old code path recovered only
    ///    1 of 25 prices on one receipt; passing the correct orientation
    ///    recovered all 25. We derive the base orientation from
    ///    `image.imageOrientation`, then ALSO try the other 3 cardinal
    ///    rotations of that (for the "user photographed the receipt lying
    ///    sideways" case, where EXIF says "normal" but the content itself
    ///    is rotated) and keep whichever trial detects the most text lines
    ///    (ties broken by confidence) — this is a much stronger signal than
    ///    confidence alone, since Vision reports high per-line confidence
    ///    regardless of orientation but segments far FEWER, more-garbled
    ///    lines on the wrong one.
    /// 2. ROW RECONSTRUCTION. Vision returns one observation per detected
    ///    text line, but a receipt's item name and its price are two
    ///    SEPARATE observations (left column / right column) — the old code
    ///    joined them in raw array order, which is NOT the same as reading
    ///    order across columns and scrambled name↔price pairing. We
    ///    cluster observations by y-proximity into rows, then sort each
    ///    row's columns left-to-right by x.
    /// 3. QUALITY GATE + ENHANCE RETRY. If the winning orientation pass is
    ///    still too sparse/low-confidence (faded thermal print, glare, low
    ///    light), retry once on a contrast-boosted, grayscale version of the
    ///    same frame before giving up.
    static func recognize(image: UIImage) async throws -> VisionReceiptOCRResult {
        guard let cgImage = image.cgImage else {
            throw VisionReceiptOCRError.invalidImage
        }
        let downsampled = Self.downsample(cgImage, maxDimension: maxOCRDimension) ?? cgImage
        let baseOrientation = image.imageOrientation.cgImagePropertyOrientation

        let (best, bestOrientation) = try await bestOrientationPass(downsampled, base: baseOrientation)

        // Quality gate: too few lines or too low confidence even on the best
        // orientation. Try one contrast/grayscale-enhanced retry before
        // giving up — this catches faded thermal print and glare/low light,
        // which respond well to a contrast boost even though we don't do a
        // full blur-detection pass (see VisionReceiptOCR.swift report notes).
        var final = best
        var finalOrientation = bestOrientation
        var usedEnhanced = false
        if Self.isLowQuality(final) {
            if let enhancedCG = Self.enhanceForOCR(downsampled) {
                let (enhancedBest, enhancedOrientation) = try await bestOrientationPass(enhancedCG, base: baseOrientation)
                if enhancedBest.lines.count > final.lines.count
                    || (enhancedBest.lines.count == final.lines.count && enhancedBest.averageConfidence > final.averageConfidence)
                {
                    final = enhancedBest
                    finalOrientation = enhancedOrientation
                    usedEnhanced = true
                }
            }
        }

        guard !final.lines.isEmpty else {
            throw VisionReceiptOCRError.noTextFound
        }
        if Self.isLowQuality(final) {
            throw VisionReceiptOCRError.tooLowQuality(
                "This photo is too blurry, dark, or faint to read reliably. Try retaking it flat, well-lit, and in focus."
            )
        }

        let rows = Self.correctRowOrderIfReversed(Self.reconstructRows(final.observations))
        let rawText = rows.map(\.text).joined(separator: "\n")
        logger.info(
            "Vision OCR: \(final.lines.count) lines, \(rows.count) rows, avg conf \(final.averageConfidence, format: .fixed(precision: 2)), orientation=\(finalOrientation.rawValue), enhanced=\(usedEnhanced)"
        )
        return VisionReceiptOCRResult(
            rawText: rawText,
            rows: rows,
            lines: final.lines,
            averageConfidence: final.averageConfidence,
            orientationUsed: Int32(finalOrientation.rawValue),
            usedEnhancedRetry: usedEnhanced
        )
    }

    // MARK: - Quality gate

    /// Fewer than this many recognized lines, or below this average
    /// confidence, is treated as "couldn't read this reliably" — a receipt
    /// photo realistically has 15+ printed lines even for a short receipt
    /// (header alone is ~6 lines), so single-digit line counts mean the shot
    /// genuinely failed (blank surface, extreme blur, wrong subject).
    private static func isLowQuality(_ result: RawOCRPass) -> Bool {
        result.lines.count < 6 || result.averageConfidence < 0.35
    }

    // MARK: - Orientation trial

    private struct RawOCRPass {
        let lines: [VisionReceiptOCRResult.Line]
        let observations: [(text: String, confidence: Double, box: CGRect)]
        let averageConfidence: Double
    }

    /// Tries the EXIF-derived base orientation plus the 3 other cardinal
    /// rotations, keeps whichever reconstructs the most distinct ROWS (ties
    /// broken by raw line count, then confidence).
    ///
    /// Line count alone is NOT a reliable orientation signal: Vision's
    /// `.accurate` recognizer can still detect dozens of short tokens
    /// (prices, single words) at high confidence even when handed the wrong
    /// rotation, because individual short tokens have some rotation
    /// tolerance. When that happens the reported bounding boxes are in the
    /// wrong coordinate frame — what should be many distinct down-the-page
    /// row positions collapses onto a handful of near-identical y-values
    /// (confirmed on a real receipt where the wrong-but-tied-on-line-count
    /// orientation produced 90 lines but only 17 rows, versus ~65 expected,
    /// because the true vertical reading axis got reported as x). Row count
    /// after `reconstructRows` directly measures whether an orientation's
    /// geometry actually looks like a real multi-row receipt, so it's a
    /// stronger correctness signal than raw line count.
    private static func bestOrientationPass(
        _ image: CGImage,
        base: CGImagePropertyOrientation
    ) async throws -> (RawOCRPass, CGImagePropertyOrientation) {
        var candidates: [CGImagePropertyOrientation] = [base, .up, .down, .left, .right]
        var seen = Set<UInt32>()
        candidates = candidates.filter { seen.insert($0.rawValue).inserted }

        var best: RawOCRPass?
        var bestRowCount = -1
        var bestOrientation: CGImagePropertyOrientation = base
        for candidate in candidates {
            let pass = try await runOCR(image, orientation: candidate)
            let rowCount = Self.reconstructRows(pass.observations).count
            if best == nil
                || rowCount > bestRowCount
                || (rowCount == bestRowCount && pass.lines.count > best!.lines.count)
                || (rowCount == bestRowCount && pass.lines.count == best!.lines.count && pass.averageConfidence > best!.averageConfidence)
            {
                best = pass
                bestRowCount = rowCount
                bestOrientation = candidate
            }
        }
        return (best ?? RawOCRPass(lines: [], observations: [], averageConfidence: 0), bestOrientation)
    }

    private static func runOCR(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> RawOCRPass {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: VisionReceiptOCRError.recognitionFailed(error.localizedDescription))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: RawOCRPass(lines: [], observations: [], averageConfidence: 0))
                    return
                }
                var lines: [VisionReceiptOCRResult.Line] = []
                var raw: [(text: String, confidence: Double, box: CGRect)] = []
                var confidenceSum: Double = 0
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else {
                        continue
                    }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty {
                        continue
                    }
                    let confidence = Double(candidate.confidence)
                    lines.append(.init(text: text, confidence: confidence))
                    raw.append((text, confidence, observation.boundingBox))
                    confidenceSum += confidence
                }
                let avg = lines.isEmpty ? 0 : confidenceSum / Double(lines.count)
                continuation.resume(returning: RawOCRPass(lines: lines, observations: raw, averageConfidence: avg))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            // Receipts can be multi-language (US English, Italian); favor English
            // but allow the recognizer to fall back when needed.
            request.recognitionLanguages = ["en-US", "it-IT"]

            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: VisionReceiptOCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Row reconstruction

    /// Groups observations into visual rows by y-proximity, then sorts each
    /// row's members left-to-right by x. Vision's boundingBox is normalized
    /// with origin bottom-left, so higher y = further up the page = earlier
    /// reading order; rows are returned top-to-bottom.
    ///
    /// The clustering threshold adapts to the receipt's own line pitch
    /// (median gap between distinct y-values) so it works across different
    /// fonts/photo scales rather than a single fixed pixel guess — but is
    /// clamped to a sane [0.004, 0.01] normalized range since receipts are
    /// fairly uniform.
    static func reconstructRows(
        _ observations: [(text: String, confidence: Double, box: CGRect)]
    ) -> [VisionReceiptOCRResult.Row] {
        guard !observations.isEmpty else {
            return []
        }
        let sortedByY = observations.sorted { $0.box.origin.y > $1.box.origin.y }

        let ys = sortedByY.map(\.box.origin.y)
        var gaps: [Double] = []
        for i in 1 ..< ys.count {
            let gap = ys[i - 1] - ys[i]
            if gap > 0.0005 {
                gaps.append(gap)
            }
        }
        let medianGap = gaps.sorted().isEmpty ? 0.006 : gaps.sorted()[gaps.count / 2]
        let threshold = min(0.01, max(0.004, medianGap * 0.6))

        var rows: [[(text: String, confidence: Double, box: CGRect)]] = []
        for obs in sortedByY {
            if let lastRow = rows.last, let anchor = lastRow.first, abs(anchor.box.origin.y - obs.box.origin.y) < threshold {
                rows[rows.count - 1].append(obs)
            } else {
                rows.append([obs])
            }
        }

        return rows.map { row in
            let ordered = row.sorted { $0.box.origin.x < $1.box.origin.x }
            let avgY = ordered.reduce(0.0) { $0 + $1.box.origin.y } / Double(ordered.count)
            let avgConf = ordered.reduce(0.0) { $0 + $1.confidence } / Double(ordered.count)
            return VisionReceiptOCRResult.Row(columns: ordered.map(\.text), yPosition: avgY, confidence: avgConf)
        }
    }

    // MARK: - Row order sanity check

    /// Phrases that only ever appear near the very end of a real receipt
    /// (payment/legal/footer boilerplate). Used only as a REVERSAL signal
    /// (see `correctRowOrderIfReversed`), never to identify a footer
    /// boundary on its own — kept short and specific so it doesn't also
    /// match plausible header content (a store's own name or website can
    /// legitimately appear near the top too).
    private static let reversalFooterMarkers = [
        "thank you for shopping",
        "terms & conditions",
        "cashier today was",
        "auth/trace",
        "receipt id",
    ]

    /// `reconstructRows` documents its output as top-to-bottom, but on some
    /// real captures (confirmed on a landscape-oriented photo of a long
    /// receipt) Vision reads every character correctly at high confidence
    /// while the row AND column geometry comes out effectively 180° from
    /// true reading order — footer boilerplate lands in the first few rows
    /// instead of the last few, and each row's price/item-name column order
    /// is swapped. Left uncorrected, every downstream consumer (raw text
    /// sent to the structuring LLM, the deterministic pre-parser's
    /// footer/voided-section boundary detection) breaks in ways that are
    /// hard to diagnose after the fact.
    ///
    /// Detect it by requiring a footer marker in the first quarter of rows
    /// AND its absence from the last quarter — both conditions, not just
    /// the first, since a marker that legitimately appears at both ends (or
    /// only near the top, e.g. a store name containing "thank you") should
    /// never trigger a reversal on an already-correct receipt.
    static func correctRowOrderIfReversed(_ rows: [VisionReceiptOCRResult.Row]) -> [VisionReceiptOCRResult.Row] {
        guard rows.count > 8 else {
            return rows
        }
        let quarter = max(1, rows.count / 4)
        func hasMarker(_ slice: ArraySlice<VisionReceiptOCRResult.Row>) -> Bool {
            slice.contains { row in
                let lower = row.text.lowercased()
                return reversalFooterMarkers.contains { lower.contains($0) }
            }
        }
        guard hasMarker(rows.prefix(quarter)), !hasMarker(rows.suffix(quarter)) else {
            return rows
        }
        return rows.reversed().map { row in
            VisionReceiptOCRResult.Row(columns: row.columns.reversed(), yPosition: row.yPosition, confidence: row.confidence)
        }
    }

    // MARK: - Downsampling

    private static func downsample(_ image: CGImage, maxDimension: CGFloat) -> CGImage? {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxDimension else {
            return image
        }
        let scale = maxDimension / longest
        let newWidth = max(1, Int(CGFloat(image.width) * scale))
        let newHeight = max(1, Int(CGFloat(image.height) * scale))
        guard let colorSpace = image.colorSpace,
              let context = CGContext(
                  data: nil,
                  width: newWidth,
                  height: newHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: image.bitmapInfo.rawValue
              )
        else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    // MARK: - Contrast/grayscale enhance (retry pass for glare/low-light/faded print)

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static func enhanceForOCR(_ image: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else {
            return nil
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        filter.setValue(1.35, forKey: kCIInputContrastKey)
        filter.setValue(0.05, forKey: kCIInputBrightnessKey)
        guard let output = filter.outputImage else {
            return nil
        }
        return ciContext.createCGImage(output, from: output.extent)
    }
}

// MARK: - UIImage.Orientation -> CGImagePropertyOrientation

extension UIImage.Orientation {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
