//
// ReceiptPhotoStore.swift
// Tempo
//
// Persists the downsampled receipt JPEG to disk so a failed structuring call
// can be retried without forcing the user to re-shoot the receipt. Lives in
// Application Support (NOT Caches — the OS purges Caches under pressure, which
// would silently break retry). One file per receipt, keyed by receipt id.
//

import Foundation
import os

// MARK: - ReceiptPhotoStore

/// Thin disk store for receipt photos. The bytes written are the *already
/// downsampled* JPEG produced for upload (`UIImage.downsampledJPEGBase64`), so
/// retry re-sends the exact payload that the backend accepts — no re-encode,
/// no second full-res copy.
enum ReceiptPhotoStore {
    private static let logger = Logger.nutrition

    /// Directory that survives Caches eviction. Created lazily.
    private static var directory: URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("ReceiptPhotos", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                logger.error("[Diag.Receipt] could not create photo dir: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return dir
    }

    private static func url(for receiptID: UUID) -> URL? {
        directory?.appendingPathComponent("\(receiptID.uuidString).jpg", isDirectory: false)
    }

    /// Write the JPEG bytes for a receipt. Returns the on-disk path string to
    /// store in `Receipt.photoPath`, or nil if the write failed (caller treats
    /// nil as "retry won't be available" — not a hard scan failure).
    @discardableResult
    static func save(_ jpeg: Data, for receiptID: UUID) -> String? {
        guard let url = url(for: receiptID) else { return nil }
        do {
            try jpeg.write(to: url, options: .atomic)
            return url.path
        } catch {
            logger.error("[Diag.Receipt] photo write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Load the persisted JPEG for a receipt, if any.
    static func load(for receiptID: UUID) -> Data? {
        guard let url = url(for: receiptID) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Delete the persisted photo. Called from `delete(_:)` — SwiftData's
    /// cascade rule removes the rows but does nothing to files on disk, so
    /// without this every receipt delete leaks an image.
    static func delete(for receiptID: UUID) {
        guard let url = url(for: receiptID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
