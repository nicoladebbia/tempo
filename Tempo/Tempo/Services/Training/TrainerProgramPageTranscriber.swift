//
// TrainerProgramPageTranscriber.swift
// Tempo
//
// TRANSCRIBE step of the Trainer Program import pipeline: sends each
// normalized page image to the existing Sonnet vision proxy for a faithful,
// row-by-row transcription (on-device Vision OCR alone drops small table
// cells like "3", "x", "8" on real trainer sheets — this is why the pipeline
// exists), with the page's on-device text (PDF text layer via
// ProgramTextExtractor.positionAwareText, or Vision OCR) sent along as a
// hint. Pages transcribe concurrently, capped at 3 in flight, so a 6-page
// import doesn't serialize into a minute-long wait but also doesn't fire 20
// requests at once. `.directText` units (pasted text, .txt/.csv files) skip
// this step — they're already legible.
//
// The combined, ordered transcript is what TrainerProgramImportService /
// TrainerProgramParser structure into a program (STRUCTURE step, unchanged
// network shape — this file only produces its input text).
//

import Foundation
import os

// MARK: - TrainerProgramPageTranscriber

enum TrainerProgramPageTranscriber {
    /// Pages transcribe concurrently, at most this many in flight.
    static let maxConcurrentPages = 3

    enum TranscribeError: Error, LocalizedError {
        case signedOut
        case api(APIError)

        var errorDescription: String? {
            switch self {
            case .signedOut: "Sign in to read programs with AI."
            case let .api(error): error.userMessage
            }
        }
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You transcribe one page of a personal trainer's training program (a \
    photo, a scanned sheet, or a photographed whiteboard — possibly Italian \
    or English, the athlete is Italian) into faithful plain text. You do \
    not structure, translate or interpret it — transcribe exactly what is \
    written, as accurately as you can. Output plain text only: no markdown, \
    no commentary before or after it.
    """

    /// `hintText` is the page's own on-device text (a PDF's text layer via
    /// position-aware extraction, or Vision OCR for an image/scanned page) —
    /// it can be imperfect or out of reading order, so it's offered as a
    /// hint the model should weigh against the image, not a transcript to
    /// copy blindly.
    static func userMessage(hintText: String?) -> String {
        var message = """
        Transcribe every piece of training content on this page: section \
        or day titles, exercise names, and every column of every table — \
        read tables row by row, one row per line, columns separated by \
        " | ", e.g. "A | Leg Press | 3 x 8 | 70% | rest - | notes here". \
        Keep exercise-letter labels (A, B, C…) when the sheet uses them — \
        they mark supersets/pairings. Keep order-of-work notes (e.g. \
        "Follow the order: S1 - Rest - S2 - Rest - S2 - Rest - S1"). \
        Include any handwritten text you can make out. Transcribe numbers \
        and symbols exactly as written — rest as "-", "60\\"", "3'", \
        percentages, reps like "8+8". Don't invent or complete anything \
        that isn't legible — write [illegible] instead. If the page has no \
        training content, say so in one line.
        """
        if let hintText {
            let trimmed = hintText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                message += """


                This page's on-device text extraction may help you read \
                faint or small text. It can be imperfect or out of reading \
                order — trust the image over this hint when they disagree:
                <hint>
                \(trimmed.prefix(4000))
                </hint>
                """
            }
        }
        return message
    }

    // MARK: - Transcribe

    /// Transcribes every `.page` unit (via the vision proxy) and passes
    /// every `.directText` unit through unchanged, then joins them in
    /// source order into one combined transcript for the STRUCTURE step.
    /// `onProgress` fires after each page finishes (`completed`, `total` —
    /// `total` counts only the units that actually need a vision call, so a
    /// mixed batch of PDFs + a pasted-text source reports progress only for
    /// the pages that are genuinely "being read").
    static func transcribe(
        units: [ProgramNormalizedUnit],
        apiClient: APIClient,
        onProgress: @Sendable @escaping (_ completed: Int, _ total: Int) -> Void
    ) async throws -> String {
        let totalPages = units.filter {
            if case .page = $0 {
                true
            } else {
                false
            }
        }.count
        var results = [Int: String](minimumCapacity: units.count)
        var completedPages = 0

        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var iterator = units.enumerated().makeIterator()

            func startNext() {
                guard let (index, unit) = iterator.next() else {
                    return
                }
                group.addTask {
                    let text = try await Self.transcribeUnit(unit, apiClient: apiClient)
                    return (index, text)
                }
            }

            for _ in 0 ..< min(maxConcurrentPages, units.count) {
                startNext()
            }
            while let (index, text) = try await group.next() {
                results[index] = text
                if case .page = units[index] {
                    completedPages += 1
                    onProgress(completedPages, totalPages)
                }
                startNext()
            }
        }

        return (0 ..< units.count)
            .compactMap { results[$0] }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n---\n\n")
    }

    private static func transcribeUnit(_ unit: ProgramNormalizedUnit, apiClient: APIClient) async throws -> String {
        switch unit {
        case let .directText(text, _):
            return text
        case let .page(imageJPEG, hintText, sourceLabel):
            do {
                let body = NutritionProxyVisionRequest(
                    model: "sonnet",
                    system: systemPrompt,
                    userMessage: userMessage(hintText: hintText),
                    imageMediaType: "image/jpeg",
                    imageBase64: imageJPEG.base64EncodedString(),
                    maxTokens: 2000,
                    temperature: 0,
                    caller: "trainer_program_transcribe"
                )
                let response: NutritionProxyTextResponse = try await apiClient.request(
                    APIEndpoint<NutritionProxyTextResponse>.nutritionProxyVision(),
                    body: body
                )
                return "[\(sourceLabel)]\n\(response.text)"
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as APIError {
                if case .unauthorized = error {
                    throw TranscribeError.signedOut
                }
                throw TranscribeError.api(error)
            }
        }
    }
}
