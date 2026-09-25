//
// ProgramTextExtractor.swift
// Tempo
//
// On-device extraction helpers feeding the Trainer Program import pipeline
// (TrainerProgramSourceNormalizer runs the actual per-source pipeline; this
// file holds the pure/testable primitives it calls):
//  - Vision OCR for photos/screenshots (reuses VisionReceiptOCR's
//    accurate-mode pattern, with language correction ON — unlike
//    abbreviated receipt SKUs, exercise-sheet prose benefits from it).
//  - Position-aware PDF text: PDFKit's own per-line selections
//    (`selectionsByLine()`), each mapped to a normalized bounding box and
//    re-ordered with `order(_:rowTolerance:)`. This matters because a real
//    trainer sheet is often two tables side by side (e.g. two exercises per
//    row) — `PDFPage.string` reads the content stream in insertion order and
//    interleaves the two tables' columns into garbage ("A Leg Press A SA
//    Incline DB Chest Press 3 x 8 3 x 8 70% - 70% 60\""); grouping by each
//    line's own visual bounds keeps every table's row intact.
//  - Page rasterization (2x) for both a scanned page with no text layer and
//    for every PDF page's own image sent to the vision transcription step.
// The observation-ordering logic is pure and Vision-free (`order` takes
// plain bounding boxes), so table layouts (sets/reps columns) can be pinned
// with fixtures without a real Vision call or a real PDF.
//

import Foundation
import PDFKit
import UIKit
import Vision

// MARK: - ProgramTextExtractor

enum ProgramTextExtractor {
    // MARK: - Errors

    enum ExtractorError: Error, LocalizedError {
        case invalidImage
        case noTextFound
        case pdfUnreadable
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidImage: "Could not read that photo."
            case .noTextFound: "No text was found in that source."
            case .pdfUnreadable: "Could not open that PDF."
            case let .recognitionFailed(detail): "Text recognition failed: \(detail)"
            }
        }
    }

    // MARK: - Text observation (pure, testable ordering)

    /// A single recognized line, decoupled from Vision's own type so the
    /// ordering logic is unit-testable with hand-built fixtures.
    struct TextObservation: Sendable {
        let text: String
        /// Vision's normalized bounding box: origin bottom-left, (0,0)-(1,1).
        let boundingBox: CGRect
    }

    /// Orders observations into reading order — top row to bottom row, left
    /// to right within a row — so a table (a sets/reps column layout) reads
    /// as a sane line instead of Vision's unordered per-observation array.
    /// Rows are formed by clustering observations whose vertical center
    /// falls within `rowTolerance` of the row's reference (its first,
    /// topmost, member), which absorbs the small baseline jitter between
    /// columns printed on the same line.
    static func order(_ observations: [TextObservation], rowTolerance: CGFloat = 0.015) -> [String] {
        guard !observations.isEmpty else {
            return []
        }
        // Vision's y axis is bottom-up; sort top (high y) to bottom (low y).
        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        var rows: [[TextObservation]] = []
        for observation in sorted {
            if let lastIndex = rows.indices.last,
               let reference = rows[lastIndex].first,
               abs(observation.boundingBox.midY - reference.boundingBox.midY) <= rowTolerance
            {
                rows[lastIndex].append(observation)
            } else {
                rows.append([observation])
            }
        }

        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .map(\.text)
                .joined(separator: "   ")
        }
    }

    // MARK: - Image OCR

    /// Recognizes text in one image. Accurate mode + language correction ON:
    /// unlike receipts, exercise names and set/rep prose benefit from
    /// Vision's language model instead of being hurt by it.
    static func recognizeLines(in image: UIImage) async throws -> [TextObservation] {
        guard let cgImage = image.cgImage else {
            throw ExtractorError.invalidImage
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: ExtractorError.recognitionFailed(error.localizedDescription))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: ExtractorError.noTextFound)
                    return
                }
                let lines: [TextObservation] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else {
                        return nil
                    }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else {
                        return nil
                    }
                    return TextObservation(text: text, boundingBox: observation.boundingBox)
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // The user is Italian; sheets/whiteboards may be in either language.
            request.recognitionLanguages = ["en-US", "it-IT"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ExtractorError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    /// OCRs one image and returns its text in reading order (one page). Used
    /// both for a photographed page and as the on-device hint for a PDF page
    /// with no text layer (a scanned sheet).
    static func extractText(from image: UIImage) async throws -> String {
        let lines = try await recognizeLines(in: image)
        guard !lines.isEmpty else {
            throw ExtractorError.noTextFound
        }
        return order(lines).joined(separator: "\n")
    }

    // MARK: - PDF: position-aware text

    /// One PDF page's text in reading order, using PDFKit's own per-line
    /// selections mapped to normalized bounding boxes and re-ordered with
    /// `order(_:rowTolerance:)`. A tighter tolerance than the OCR default
    /// (0.006 vs 0.015) is deliberate: PDFKit's line detection is precise
    /// (unlike Vision's per-character baseline jitter), so a small
    /// tolerance is enough to catch genuine same-row wrapping without
    /// merging two visually-close-but-distinct lines.
    static func positionAwareLines(on page: PDFPage) -> [String] {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0,
              let pageSelection = page.selection(for: bounds)
        else {
            return []
        }
        let observations: [TextObservation] = pageSelection.selectionsByLine().compactMap { line in
            let text = line.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                return nil
            }
            let lineBounds = line.bounds(for: page)
            guard lineBounds.width > 0, lineBounds.height > 0 else {
                return nil
            }
            let normalized = CGRect(
                x: lineBounds.minX / bounds.width,
                y: lineBounds.minY / bounds.height,
                width: lineBounds.width / bounds.width,
                height: lineBounds.height / bounds.height
            )
            return TextObservation(text: text, boundingBox: normalized)
        }
        return order(observations, rowTolerance: 0.006)
    }

    /// One PDF page's text layer, position-aware-ordered, or nil when the
    /// page has no text layer at all (a scanned sheet — caller should fall
    /// back to Vision OCR on the rendered page image).
    static func positionAwareText(on page: PDFPage) -> String? {
        let lines = positionAwareLines(on: page)
        guard !lines.isEmpty else {
            return nil
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - PDF: page rasterization

    /// Rasterizes a PDF page to an image at `scale` — used both as OCR input
    /// for a page with no text layer and as the image every PDF page sends
    /// to the vision transcription step.
    static func renderImage(for page: PDFPage, scale: CGFloat = 2.0) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }
}
