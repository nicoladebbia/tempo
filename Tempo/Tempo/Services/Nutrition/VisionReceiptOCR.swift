//
// VisionReceiptOCR.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import os
import UIKit
import Vision

// MARK: - VisionReceiptOCRError

enum VisionReceiptOCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed(String)
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Could not read the receipt photo."
        case let .recognitionFailed(detail): "Vision recognition failed: \(detail)"
        case .noTextFound: "No text was detected on this photo."
        }
    }
}

// MARK: - VisionReceiptOCRResult

struct VisionReceiptOCRResult: Sendable {
    /// All text lines in vertical reading order, joined with newlines.
    let rawText: String
    /// Per-line entries kept for structuring debug + confidence-weighted re-parsing.
    let lines: [Line]
    /// Average confidence across all recognized lines (0.0–1.0).
    let averageConfidence: Double

    struct Line: Sendable {
        let text: String
        let confidence: Double
    }
}

// MARK: - VisionReceiptOCR

enum VisionReceiptOCR {
    private static let logger = Logger.nutrition

    /// Recognize text in a receipt photo. Uses Vision's `accurate` mode with
    /// language correction off (receipts are abbreviated; language modelling
    /// hurts SKU lines more than it helps).
    static func recognize(image: UIImage) async throws -> VisionReceiptOCRResult {
        guard let cgImage = image.cgImage else {
            throw VisionReceiptOCRError.invalidImage
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: VisionReceiptOCRError.recognitionFailed(error.localizedDescription))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(throwing: VisionReceiptOCRError.noTextFound)
                    return
                }

                var lines: [VisionReceiptOCRResult.Line] = []
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
                    confidenceSum += confidence
                }

                guard !lines.isEmpty else {
                    continuation.resume(throwing: VisionReceiptOCRError.noTextFound)
                    return
                }

                let rawText = lines.map(\.text).joined(separator: "\n")
                let averageConfidence = confidenceSum / Double(lines.count)
                logger.info("Vision OCR: \(lines.count) lines, avg conf \(averageConfidence, format: .fixed(precision: 2))")
                continuation.resume(returning: .init(
                    rawText: rawText,
                    lines: lines,
                    averageConfidence: averageConfidence
                ))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            // Receipts can be multi-language (US English, Italian); favor English
            // but allow the recognizer to fall back when needed.
            request.recognitionLanguages = ["en-US", "it-IT"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: VisionReceiptOCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }
}
