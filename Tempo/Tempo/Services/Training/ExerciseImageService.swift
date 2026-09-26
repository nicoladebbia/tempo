//
// ExerciseImageService.swift
// Tempo
//

import Foundation
import os

// MARK: - ExerciseImageService

//
// Resolves `baseURL/v1/exercise-images/<slug>` for an exercise, backed by a
// disk cache (Caches/ExerciseImages, keyed by slug — OK to lose under disk
// pressure, images are re-fetchable from the backend). On a 404 it asks the
// backend to generate the image via the authed POST, then re-fetches.
//
// Contract (per feat/exercise-images): never throws, at most one in-flight
// request per slug, remembers failures for the session (no hammering), and
// silently returns nil when signed out or the backend answers 429/503/any
// other error — callers (ExerciseImageView) show the equipment-icon
// placeholder in every "no image" case, there's no error UI for this.

@MainActor
@Observable
final class ExerciseImageService {
    private let apiClient: APIClient
    /// MainActor-isolated, not @Sendable — ExerciseImageService itself is
    /// @MainActor, so this only ever runs on that actor. Kept as a closure
    /// (rather than depending on AuthService directly) so tests can inject
    /// a fixed signed-in/out value without a real AuthService.
    private let isSignedIn: () -> Bool
    private let session: URLSession
    private let cacheDirectoryOverride: URL?
    private let logger = Logger(subsystem: "app.tempo", category: "ExerciseImageService")

    /// One in-flight fetch/generate Task per slug — a second caller for the
    /// same slug joins this Task instead of firing a duplicate request.
    private var inFlight: [String: Task<Data?, Never>] = [:]

    /// Slugs that failed this session. Not retried again until relaunch, so
    /// an offline device or an exhausted budget doesn't get hammered on
    /// every row redraw (Today's list, library, active workout...).
    private var failedSlugs: Set<String> = []

    init(
        apiClient: APIClient,
        isSignedIn: @escaping () -> Bool,
        session: URLSession = .shared,
        cacheDirectoryOverride: URL? = nil
    ) {
        self.apiClient = apiClient
        self.isSignedIn = isSignedIn
        self.session = session
        self.cacheDirectoryOverride = cacheDirectoryOverride
    }

    // MARK: - Public API

    /// Image bytes for `exercise`, from disk cache / the backend / freshly
    /// generated — or nil if none is available right now. Never throws.
    /// Convenience overload — converts to the Sendable `ExerciseImageInput`
    /// immediately (on the caller's context) before doing anything async, so
    /// the non-Sendable `Exercise`/other conforming type never has to cross
    /// a concurrency boundary itself.
    func imageData(for exercise: any ExerciseImageDescribing) async -> Data? {
        await imageData(for: exercise.imageInput)
    }

    /// Same as above, taking the Sendable value directly — the form to use
    /// from anywhere that isn't already holding a live `Exercise` (or that
    /// needs to call this from a context where sending a non-Sendable model
    /// around would itself be the Swift 6 concurrency violation).
    func imageData(for input: ExerciseImageInput) async -> Data? {
        let slug = ExerciseImageSlug.make(from: input.name)
        guard !slug.isEmpty else {
            return nil
        }

        if let cached = readFromDisk(slug: slug) {
            return cached
        }
        if failedSlugs.contains(slug) {
            return nil
        }
        if let existing = inFlight[slug] {
            return await existing.value
        }

        let task = Task<Data?, Never> { [weak self] in
            await self?.fetchOrGenerate(slug: slug, input: input)
        }
        inFlight[slug] = task
        let result = await task.value
        inFlight[slug] = nil
        return result
    }

    /// True once a (session-remembered) failure or a successful fetch has
    /// already resolved this exercise's image — used by "Generate missing
    /// exercise pictures" to skip slugs it already knows about this run.
    func hasCachedOrFailedResult(for exercise: any ExerciseImageDescribing) -> Bool {
        let slug = ExerciseImageSlug.make(from: exercise.imageInput.name)
        return failedSlugs.contains(slug) || readFromDisk(slug: slug) != nil
    }

    // MARK: - Fetch / generate

    private func fetchOrGenerate(slug: String, input: ExerciseImageInput) async -> Data? {
        if let data = await fetchRemoteBytes(slug: slug) {
            writeToDisk(slug: slug, data: data)
            return data
        }

        guard isSignedIn() else {
            failedSlugs.insert(slug)
            return nil
        }

        let body = ExerciseImageGenerateRequestDTO(
            name: input.name,
            equipment: input.equipmentRaw,
            muscleGroup: input.muscleGroupRaw,
            movementPattern: input.movementPatternRaw,
            instructions: input.instructions
        )

        do {
            _ = try await apiClient.request(
                APIEndpoint<ExerciseImageGenerateResponseDTO>.generateExerciseImage(),
                body: body
            )
        } catch {
            // Signed out mid-flight (.unauthorized), rate-limited (.rateLimited),
            // not configured / budget exhausted (.serverError 503), or any other
            // transport error — all silent per contract. Session-memoized either
            // way so a broken path doesn't retry on every redraw.
            logger.debug("generate failed for \(slug, privacy: .public): \(String(describing: error), privacy: .public)")
            failedSlugs.insert(slug)
            return nil
        }

        if let data = await fetchRemoteBytes(slug: slug) {
            writeToDisk(slug: slug, data: data)
            return data
        }
        failedSlugs.insert(slug)
        return nil
    }

    private func fetchRemoteBytes(slug: String) async -> Data? {
        let url = AppConstants.apiBaseURL.appendingPathComponent("v1/exercise-images/\(slug)")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Disk cache

    private func cacheDirectory() -> URL? {
        if let override = cacheDirectoryOverride {
            try? FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("ExerciseImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func fileURL(for slug: String) -> URL? {
        cacheDirectory()?.appendingPathComponent("\(slug).jpg")
    }

    private func readFromDisk(slug: String) -> Data? {
        guard let url = fileURL(for: slug) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func writeToDisk(slug: String, data: Data) {
        guard let url = fileURL(for: slug) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - ExerciseImageInput

/// Sendable snapshot of whatever describes an exercise's image-generation
/// inputs — the ACTUAL type ExerciseImageService's async methods operate on
/// internally. `Exercise` (SwiftData) is a class and not Sendable, so it's
/// converted to this at the call boundary (`ExerciseImageDescribing.imageInput`)
/// before anything crosses an async/Task boundary.
struct ExerciseImageInput: Sendable, Equatable {
    let name: String
    let equipmentRaw: String
    let muscleGroupRaw: String
    let movementPatternRaw: String?
    let instructions: String?
}

// MARK: - ExerciseImageDescribing

/// Minimal facade over whatever can produce an `ExerciseImageInput`.
/// `Exercise` (SwiftData) conforms below.
protocol ExerciseImageDescribing {
    var imageInput: ExerciseImageInput { get }
}

// MARK: - Exercise + ExerciseImageDescribing

extension Exercise: ExerciseImageDescribing {
    var imageInput: ExerciseImageInput {
        ExerciseImageInput(
            name: name,
            equipmentRaw: equipmentRaw,
            muscleGroupRaw: muscleGroupRaw,
            movementPatternRaw: movementPatternRaw,
            instructions: instructions
        )
    }
}
