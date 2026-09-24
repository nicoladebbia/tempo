//
// TrainerProgramImportBatching.swift
// Tempo
//
// Pure grouping logic for the Trainer Program TRANSCRIBE step (fix #2): the
// backend's /v1/training/program-import/transcribe route accepts up to 5
// images per request with a combined raw-byte budget of ~4.5MB, so a
// multi-page import batches its page images instead of sending one network
// request per page (which could exhaust a tight per-minute rate limit
// mid-import). No Foundation networking types here — just int arithmetic —
// so it's directly unit-testable.
//

import Foundation

// MARK: - TrainerProgramImportBatching

enum TrainerProgramImportBatching {
    /// Matches the backend's TrainingProgramImportController.maxImagesPerRequest.
    static let maxImagesPerBatch = 5
    /// Kept under the backend's ~4.5MB cap so base64/JSON overhead on top of
    /// this never trips the server's own size guard.
    static let maxBatchRawBytes = 4 * 1024 * 1024
    /// At most this many batches transcribe concurrently.
    static let maxConcurrentBatches = 2

    /// Groups `sizes` (raw JPEG byte counts, in original order) into batches
    /// of at most `maxImagesPerBatch` images each, additionally starting a
    /// new batch early — before hitting the count cap — if adding the next
    /// image would push the running byte total over `maxBatchBytes`. Returns
    /// arrays of ORIGINAL INDICES into `sizes`, preserving order both within
    /// and across batches.
    ///
    /// A single image whose own size already exceeds `maxBatchBytes` becomes
    /// a solo batch (it can't be packed with anything else) — the caller is
    /// expected to downscale it further before sending; see
    /// `TrainerProgramPageTranscriber.shrinkIfOversized`.
    static func plan(
        sizes: [Int],
        maxImagesPerBatch: Int = maxImagesPerBatch,
        maxBatchBytes: Int = maxBatchRawBytes
    ) -> [[Int]] {
        var batches: [[Int]] = []
        var current: [Int] = []
        var currentBytes = 0

        for (index, size) in sizes.enumerated() {
            let hitsCountCap = current.count >= maxImagesPerBatch
            let hitsByteCap = !current.isEmpty && (currentBytes + size) > maxBatchBytes
            if hitsCountCap || hitsByteCap {
                batches.append(current)
                current = []
                currentBytes = 0
            }
            current.append(index)
            currentBytes += size
        }
        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }
}
