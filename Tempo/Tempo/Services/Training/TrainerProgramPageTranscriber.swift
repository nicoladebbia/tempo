//
// TrainerProgramPageTranscriber.swift
// Tempo
//
// TRANSCRIBE step of the Trainer Program import pipeline: page images go
// through the Sonnet vision proxy (POST /v1/training/program-import/
// transcribe) for a faithful, row-by-row transcription — on-device Vision
// OCR alone drops small table cells like "3", "x", "8" on real trainer
// sheets, which is why the pipeline exists at all — with the page's
// on-device text (PDF text layer via ProgramTextExtractor.positionAwareText,
// or Vision OCR) sent along as a hint. `.directText` units (pasted text,
// .txt/.csv files) skip this step entirely — they're already legible.
//
// Fix #2: pages are sent in BATCHES of up to 5 images (one Claude call per
// batch, TrainerProgramImportBatching.plan), not one request per page — a
// 12-page import used to fire 12 requests against a shared 20/min limit and
// could exhaust it mid-import. Batches transcribe concurrently, capped at 2
// in flight. A batch that hits a 429 retries with Retry-After (or a 2s/4s/8s
// backoff, max 3 attempts) WITHOUT re-sending any other batch — already-
// transcribed pages are never re-requested.
//
// The combined, ordered transcript is what TrainerProgramImportService /
// TrainerProgramParser structure into a program (STRUCTURE step) — this
// file only produces its input text.
//

import Foundation
import os

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - TrainerProgramPageTranscriber

enum TrainerProgramPageTranscriber {
    /// Batches transcribe concurrently, at most this many in flight.
    static let maxConcurrentBatches = TrainerProgramImportBatching.maxConcurrentBatches
    /// Per-batch retry attempts after the first try (2s/4s/8s backoff, or
    /// Retry-After when the server sends one).
    static let maxRetriesPerBatch = 3

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
    You transcribe pages of a personal trainer's training program (photos, \
    scanned sheets, or photographed whiteboards — possibly Italian or \
    English, the athlete is Italian) into faithful plain text. You do not \
    structure, translate or interpret it — transcribe exactly what is \
    written, as accurately as you can. Output plain text only: no markdown, \
    no commentary before or after it.
    """

    /// The shared instruction sent with every batch. Asks the model to
    /// separate each page's transcription with a "=== PAGE n ===" sentinel
    /// (n = 1-based position within THIS batch) so the backend can split the
    /// completion back into one string per image, in the order they were
    /// sent. Per-page on-device text hints travel as their own request field
    /// (not embedded here) — the backend interleaves them next to their
    /// matching image.
    static func batchUserMessage(pageCount: Int) -> String {
        let sentinelInstruction = pageCount > 1
            ? """
            You will receive \(pageCount) images, in order. Transcribe EACH \
            one separately. Immediately before each page's transcription, \
            output its own line reading exactly "=== PAGE n ===" (n = 1 for \
            the first image, 2 for the second, and so on). Output nothing \
            else outside these page blocks — no preamble, no summary.
            """
            : """
            Immediately before the transcription, output a line reading \
            exactly "=== PAGE 1 ===". Output nothing else outside that page \
            block.
            """
        return """
        \(sentinelInstruction)

        For each page, transcribe every piece of training content: section \
        or day titles, exercise names, and every column of every table — \
        read tables row by row, one row per line, columns separated by \
        " | ", e.g. "A | Leg Press | 3 x 8 | 70% | rest - | notes here". \
        Keep exercise-letter labels (A, B, C…) when the sheet uses them — \
        they mark supersets/pairings. Keep order-of-work notes (e.g. \
        "Follow the order: S1 - Rest - S2 - Rest - S2 - Rest - S1"). \
        Include any handwritten text you can make out. Transcribe numbers \
        and symbols exactly as written — rest as "-", "60\\"", "3'", \
        percentages, reps like "8+8". Don't invent or complete anything \
        that isn't legible — write [illegible] instead. If a page has no \
        training content, say so in one line under that page's marker. \
        Some pages may include an on-device text hint alongside the image — \
        it can be imperfect or out of reading order; trust the image over \
        the hint when they disagree.
        """
    }

    // MARK: - Retry policy (pure)

    /// Delay before the next attempt, or nil to give up. `attempt` is the
    /// number of retries ALREADY made (0 on the first failure). Honors the
    /// server's Retry-After when present; otherwise 2s/4s/8s. Returns nil
    /// once `attempt >= maxRetriesPerBatch`.
    static func retryDelay(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval? {
        guard attempt < maxRetriesPerBatch else {
            return nil
        }
        if let retryAfter, retryAfter > 0 {
            return retryAfter
        }
        let backoffTable: [TimeInterval] = [2, 4, 8]
        return backoffTable[min(attempt, backoffTable.count - 1)]
    }

    // MARK: - Page item / batching

    /// One page image ready to be grouped into a batch. `unitIndex` is its
    /// position in the ORIGINAL `units` array — batching only reorders
    /// pages within contiguous runs, never across a `.directText` unit, so
    /// this is how a batch's results get spliced back into overall order.
    struct PageItem: Sendable {
        let unitIndex: Int
        let imageJPEG: Data
        let hintText: String?
        let sourceLabel: String
    }

    /// Groups `pages` into contiguous batches per `TrainerProgramImportBatching.plan`.
    static func planBatches(_ pages: [PageItem]) -> [[PageItem]] {
        let indexBatches = TrainerProgramImportBatching.plan(sizes: pages.map(\.imageJPEG.count))
        return indexBatches.map { indices in indices.map { pages[$0] } }
    }

    #if canImport(UIKit)
        /// Best-effort further downscale for a single image that alone exceeds
        /// the batch byte budget (it can't be packed with anything else, so
        /// splitting into a smaller batch — the planner's usual strategy — can't
        /// help). Tries progressively smaller edge/quality pairs; returns the
        /// original data unchanged if it can't decode, and the smallest attempt
        /// even if still over budget rather than silently dropping the page.
        @MainActor
        static func shrinkIfOversized(_ imageJPEG: Data, maxBytes: Int = TrainerProgramImportBatching.maxBatchRawBytes) -> Data {
            guard imageJPEG.count > maxBytes else {
                return imageJPEG
            }
            guard let image = UIImage(data: imageJPEG) else {
                return imageJPEG
            }
            let attempts: [(edge: CGFloat, quality: CGFloat)] = [(1400, 0.6), (1000, 0.5), (800, 0.4)]
            var smallest = imageJPEG
            for attempt in attempts {
                guard let shrunk = image.downsampledJPEGData(maxEdge: attempt.edge, quality: attempt.quality) else {
                    continue
                }
                smallest = shrunk
                if shrunk.count <= maxBytes {
                    return shrunk
                }
            }
            return smallest
        }
    #endif

    // MARK: - Transcribe (testable core)

    /// Core orchestration with `send`/`sleep` injected — lets tests drive
    /// retry/resume behavior with a fake network layer and no real delays.
    /// `send` receives one batch's page items and must return one text per
    /// item, in the same order (a page failing to come back is filled with
    /// an "[illegible]" placeholder rather than silently dropped).
    static func transcribe(
        units: [ProgramNormalizedUnit],
        onProgress: @Sendable @escaping (_ startPage: Int, _ endPage: Int, _ totalPages: Int) -> Void,
        sleep: @Sendable @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
        send: @Sendable @escaping ([PageItem]) async throws -> [String]
    ) async throws -> String {
        // `let`, not `var` — this is built once and never mutated again, but
        // it's captured by the task group's child closures below; a `var`
        // capture there is flagged under Swift 6 strict concurrency as a
        // potential data race even though nothing actually mutates it after
        // this point.
        let pageItems: [PageItem] = units.enumerated().compactMap { index, unit in
            guard case let .page(imageJPEG, hintText, sourceLabel) = unit else {
                return nil
            }
            return PageItem(unitIndex: index, imageJPEG: imageJPEG, hintText: hintText, sourceLabel: sourceLabel)
        }

        var results = [Int: String](minimumCapacity: units.count)
        for (index, unit) in units.enumerated() {
            if case let .directText(text, _) = unit {
                results[index] = text
            }
        }

        let batches = planBatches(pageItems)
        let totalPages = pageItems.count

        try await withThrowingTaskGroup(of: (batch: [PageItem], texts: [String]).self) { group in
            var iterator = batches.makeIterator()

            func startNext() {
                guard let batch = iterator.next() else {
                    return
                }
                group.addTask {
                    try Task.checkCancellation()
                    let startPage = pageNumber(of: batch.first!, in: pageItems)
                    let endPage = pageNumber(of: batch.last!, in: pageItems)
                    onProgress(startPage, endPage, totalPages)
                    let texts = try await Self.sendWithRetry(batch, send: send, sleep: sleep)
                    return (batch, texts)
                }
            }

            for _ in 0 ..< min(maxConcurrentBatches, batches.count) {
                startNext()
            }
            while let (batch, texts) = try await group.next() {
                for (offset, item) in batch.enumerated() {
                    let text = offset < texts.count ? texts[offset] : "[illegible]"
                    results[item.unitIndex] = "[\(item.sourceLabel)]\n\(text)"
                }
                startNext()
            }
        }

        return (0 ..< units.count)
            .compactMap { results[$0] }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n---\n\n")
    }

    private static func pageNumber(of item: PageItem, in pageItems: [PageItem]) -> Int {
        (pageItems.firstIndex { $0.unitIndex == item.unitIndex } ?? 0) + 1
    }

    /// Runs `send(batch)`, retrying per `retryDelay` on a retryable
    /// `APIError` (rate-limited or transient server/network error). Only
    /// THIS batch is retried — other in-flight/completed batches are
    /// untouched, so a 429 never restarts the whole import. Note this
    /// layers on top of `APIClient`'s own per-HTTP-call retry (short
    /// 1s/2s/4s backoff inside a single request); this is the outer,
    /// batch-level policy the import pipeline owns per the product spec
    /// (honor Retry-After, else 2s/4s/8s, max 3 attempts).
    private static func sendWithRetry(
        _ batch: [PageItem],
        send: @Sendable @escaping ([PageItem]) async throws -> [String],
        sleep: @Sendable @escaping (TimeInterval) async -> Void
    ) async throws -> [String] {
        var attempt = 0
        while true {
            do {
                return try await send(batch)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as APIError {
                if case .unauthorized = error {
                    throw TranscribeError.signedOut
                }
                let retryAfter: TimeInterval? = if case let .rateLimited(after) = error {
                    after
                } else {
                    nil
                }
                guard error.isRetryable, let delay = retryDelay(attempt: attempt, retryAfter: retryAfter) else {
                    throw TranscribeError.api(error)
                }
                attempt += 1
                await sleep(delay)
            }
        }
    }

    // MARK: - Transcribe (network entry point)

    /// Real network entry point. `sessionID` is shared with the STRUCTURE
    /// call (TrainerProgramImportService) so the backend counts this whole
    /// import as ONE quota slot regardless of how many batches it takes.
    static func transcribe(
        units: [ProgramNormalizedUnit],
        apiClient: APIClient,
        sessionID: String,
        onProgress: @Sendable @escaping (_ startPage: Int, _ endPage: Int, _ totalPages: Int) -> Void
    ) async throws -> String {
        try await transcribe(units: units, onProgress: onProgress) { batch in
            try await Self.sendBatchOverNetwork(batch, apiClient: apiClient, sessionID: sessionID)
        }
    }

    private static func sendBatchOverNetwork(
        _ batch: [PageItem],
        apiClient: APIClient,
        sessionID: String
    ) async throws -> [String] {
        #if canImport(UIKit)
            let images = await batch.asyncMap { item -> ProgramImportImageInputDTO in
                let jpeg = await Self.shrinkIfOversized(item.imageJPEG)
                return ProgramImportImageInputDTO(mediaType: "image/jpeg", base64: jpeg.base64EncodedString())
            }
        #else
            let images = batch.map {
                ProgramImportImageInputDTO(mediaType: "image/jpeg", base64: $0.imageJPEG.base64EncodedString())
            }
        #endif
        let body = ProgramImportTranscribeRequestDTO(
            sessionID: sessionID,
            images: images,
            hintTexts: batch.map(\.hintText),
            system: systemPrompt,
            userMessage: batchUserMessage(pageCount: batch.count)
        )
        let response: ProgramImportTranscribeResponseDTO = try await apiClient.request(
            APIEndpoint<ProgramImportTranscribeResponseDTO>.trainerProgramImportTranscribe(),
            body: body
        )
        return response.pages
    }
}

// MARK: - Sequential async map (small helper, avoids pulling in a dependency)

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self {
            try await result.append(transform(element))
        }
        return result
    }
}
