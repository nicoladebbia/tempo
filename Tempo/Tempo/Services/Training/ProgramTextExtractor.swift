//
// ProgramTextExtractor.swift
// Tempo
//
// On-device text extraction for Trainer Program import: Vision OCR for
// photos/screenshots (reuses VisionReceiptOCR's accurate-mode pattern, with
// language correction ON — unlike abbreviated receipt SKUs, exercise-sheet
// prose benefits from it), PDFKit for PDF text layers (falling back to
// render + OCR for a scanned page with no text layer), and pasted text
// as-is. The observation-ordering logic is pure and Vision-free (`order`
// takes plain bounding boxes), so table layouts (sets/reps columns) can be
// pinned with fixtures without a real Vision call.
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

    /// OCRs one image and returns its text in reading order (one page).
    static func extractText(from image: UIImage) async throws -> String {
        let lines = try await recognizeLines(in: image)
        guard !lines.isEmpty else {
            throw ExtractorError.noTextFound
        }
        return order(lines).joined(separator: "\n")
    }

    /// OCRs several images (photos of consecutive pages/sheets) and joins
    /// them as separate pages.
    static func extractText(from images: [UIImage]) async throws -> String {
        var pages: [String] = []
        for image in images {
            try await pages.append(extractText(from: image))
        }
        guard !pages.isEmpty else {
            throw ExtractorError.noTextFound
        }
        return pages.joined(separator: "\n\n")
    }

    // MARK: - PDF

    /// Extracts text from a PDF: each page's own text layer when present,
    /// otherwise the page is rendered to an image and OCR'd (a scanned
    /// sheet has no text layer at all).
    static func extractText(fromPDFAt url: URL) async throws -> String {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let document = PDFDocument(url: url) else {
            throw ExtractorError.pdfUnreadable
        }
        var pages: [String] = []
        for index in 0 ..< document.pageCount {
            guard let page = document.page(at: index) else {
                continue
            }
            if let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                pages.append(text)
            } else if let image = renderToImage(page) {
                try await pages.append(extractText(from: image))
            }
        }
        guard !pages.isEmpty else {
            throw ExtractorError.noTextFound
        }
        return pages.joined(separator: "\n\n")
    }

    /// Rasterizes a PDF page with no text layer (a scanned sheet) at 2x so
    /// OCR has legible input.
    private static func renderToImage(_ page: PDFPage, scale: CGFloat = 2.0) -> UIImage? {
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
