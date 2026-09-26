import Fluent
import Redis
import Vapor

// MARK: - ExerciseImageService

//
// Orchestrates GET-or-generate for one exercise's image:
//   1. Existing row -> return ready immediately (idempotent).
//   2. Per-user daily limit (Redis counter, mirrors InsightController's
//      checkDailyAILimit).
//   3. Redis lock so two concurrent requests for the same slug don't both
//      pay for generation; a DB unique-insert on `slug` is the hard
//      backstop if the lock race is lost anyway.
//   4. Global monthly budget gate (ExerciseImageBudgetTracker).
//   5. Generate via the injected ExerciseImageGenerating, persist, record
//      spend + daily usage.
//
// The generator is injected (default OpenAIImageGenerator) precisely so
// tests never touch the real API — see ExerciseImageGenerating.swift.

final class ExerciseImageService: @unchecked Sendable {
    static let shared = ExerciseImageService()

    static let dailyPerUserLimit = 40
    static let lockTTLSeconds = 90

    enum ServiceError: Error, Equatable {
        case notConfigured
        case dailyLimitReached
        case budgetExhausted
        case generationInProgress
    }

    private let generator: any ExerciseImageGenerating

    init(generator: any ExerciseImageGenerating = OpenAIImageGenerator()) {
        self.generator = generator
    }

    // MARK: - Public API

    /// CLI-only path (`generate-exercise-images`). No per-user daily limit
    /// and no Redis dedupe lock — the CLI walks the library sequentially
    /// with a delay between calls, so there's no concurrent-request race to
    /// guard against. Still budget-gated and still checks for an existing
    /// row first, so re-running the command is a cheap no-op per slug.
    func generateForLibrary(
        name: String,
        equipment: String,
        muscleGroup: String,
        movementPattern: String?,
        instructions: String?,
        on req: Request
    ) async throws -> ExerciseImageResponseDTO {
        let slug = ExerciseImageSlug.make(from: name)
        let baseURL = Self.publicBaseURL(req: req)
        return try await generateAndPersist(
            slug: slug,
            name: name,
            equipment: equipment,
            muscleGroup: muscleGroup,
            movementPattern: movementPattern,
            instructions: instructions,
            baseURL: baseURL,
            userID: "cli-backfill",
            on: req
        )
    }

    func getOrGenerate(
        name: String,
        equipment: String,
        muscleGroup: String,
        movementPattern: String?,
        instructions: String?,
        userID: String,
        on req: Request
    ) async throws -> ExerciseImageResponseDTO {
        let slug = ExerciseImageSlug.make(from: name)
        let baseURL = Self.publicBaseURL(req: req)

        if try await ExerciseImage.find(slug, on: req.db) != nil {
            return .ready(slug: slug, baseURL: baseURL)
        }

        try await checkDailyLimit(userID: userID, on: req)

        guard await acquireLock(slug: slug, on: req) else {
            if try await waitForRow(slug: slug, on: req) != nil {
                return .ready(slug: slug, baseURL: baseURL)
            }
            throw ServiceError.generationInProgress
        }

        do {
            let response = try await generateAndPersist(
                slug: slug,
                name: name,
                equipment: equipment,
                muscleGroup: muscleGroup,
                movementPattern: movementPattern,
                instructions: instructions,
                baseURL: baseURL,
                userID: userID,
                on: req
            )
            await releaseLock(slug: slug, on: req)
            return response
        } catch {
            await releaseLock(slug: slug, on: req)
            throw error
        }
    }

    // MARK: - Generate + persist (lock already held)

    private func generateAndPersist(
        slug: String,
        name: String,
        equipment: String,
        muscleGroup: String,
        movementPattern: String?,
        instructions: String?,
        baseURL: String,
        userID: String,
        on req: Request
    ) async throws -> ExerciseImageResponseDTO {
        // Re-check: another request may have finished between our first
        // read and acquiring the lock.
        if try await ExerciseImage.find(slug, on: req.db) != nil {
            return .ready(slug: slug, baseURL: baseURL)
        }

        guard await ExerciseImageBudgetTracker.shared.canGenerate(on: req) else {
            throw ServiceError.budgetExhausted
        }

        let prompt = ExerciseImagePrompt.build(
            name: name,
            equipment: equipment,
            muscleGroup: muscleGroup,
            movementPattern: movementPattern,
            instructions: instructions
        )

        let generated: GeneratedExerciseImage
        do {
            generated = try await generator.generateImage(prompt: prompt, on: req)
        } catch ExerciseImageGenerationError.notConfigured {
            throw ServiceError.notConfigured
        }

        let row = ExerciseImage(slug: slug, contentType: generated.contentType, image: generated.data, prompt: prompt)
        do {
            try await row.create(on: req.db)
        } catch {
            // Unique-violation backstop: someone beat us to it despite the lock.
            if try await ExerciseImage.find(slug, on: req.db) != nil {
                return .ready(slug: slug, baseURL: baseURL)
            }
            throw error
        }

        await ExerciseImageBudgetTracker.shared.recordSpend(on: req)
        await incrementDailyLimit(userID: userID, on: req)

        req.logger.info("[exercise_image] generated slug=\(slug) bytes=\(generated.data.count)")
        return .ready(slug: slug, baseURL: baseURL)
    }

    // MARK: - Per-user daily limit (Redis, mirrors InsightController)

    //
    // check-then-later-increment, not atomic: a burst of concurrent requests
    // for DIFFERENT slugs from the same user could all pass this check
    // before any of their increments land, temporarily exceeding
    // dailyPerUserLimit. Accepted (same shape as InsightController's
    // existing checkDailyAILimit) — the per-route RateLimitMiddleware(limit:
    // 40, window: .minutes(1)) on POST /v1/exercise-images bounds how large
    // that burst can even be, and this is a soft usage cap, not a security
    // boundary. A hard guarantee would need a Lua script (atomic
    // check-and-increment), not worth the complexity here.

    private func checkDailyLimit(userID: String, on req: Request) async throws {
        let key = RedisKey("image_gen_limit:\(userID):\(Self.todayString())")
        let count = (try? await req.redis.get(key, as: Int.self).get()) ?? 0
        guard count < Self.dailyPerUserLimit else {
            throw ServiceError.dailyLimitReached
        }
    }

    private func incrementDailyLimit(userID: String, on req: Request) async {
        let key = RedisKey("image_gen_limit:\(userID):\(Self.todayString())")
        _ = try? await req.redis.increment(key).get()
        _ = try? await req.redis.expire(key, after: .seconds(24 * 3600)).get()
    }

    // MARK: - Dedup lock

    private func acquireLock(slug: String, on req: Request) async -> Bool {
        let key = RedisKey("image_gen_lock:\(slug)")
        // SETNX is the atomic check-and-set Redis provides for exactly this
        // (a plain GET then SETEX has a TOCTOU window: two concurrent
        // requests can both see the key missing and both proceed to call
        // OpenAI). If setnx fails for some reason (fail-closed on error, not
        // fail-open — mistakenly granting the lock is the expensive mistake
        // here), treat it as "did not acquire" so the caller falls into the
        // wait-for-the-other-request path instead of paying twice.
        guard let acquired = try? await req.redis.setnx(key, to: "1").get(), acquired else {
            return false
        }
        _ = try? await req.redis.expire(key, after: .seconds(Int64(Self.lockTTLSeconds))).get()
        return true
    }

    private func releaseLock(slug: String, on req: Request) async {
        _ = try? await req.redis.delete(RedisKey("image_gen_lock:\(slug)")).get()
    }

    /// Polls for another in-flight request's row to appear. Generation is
    /// synchronous and takes ~10-30s, so this bounds at lockTTLSeconds.
    private func waitForRow(slug: String, on req: Request) async throws -> ExerciseImage? {
        for _ in 0 ..< Self.lockTTLSeconds {
            if let row = try await ExerciseImage.find(slug, on: req.db) {
                return row
            }
            try await Task.sleep(for: .seconds(1))
        }
        return nil
    }

    // MARK: - Helpers

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func publicBaseURL(req: Request) -> String {
        if let configured = Environment.get("PUBLIC_BASE_URL"), !configured.isEmpty {
            return configured
        }
        let scheme = req.headers.first(name: "X-Forwarded-Proto") ?? "https"
        let host = req.headers.first(name: .host) ?? "localhost:8080"
        return "\(scheme)://\(host)"
    }
}
