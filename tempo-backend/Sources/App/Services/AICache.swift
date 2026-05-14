import Fluent
import Foundation
import Redis
import Vapor

// MARK: - AICache
//
// Per AI_INTELLIGENCE_ENGINE.md §6 + INTELLIGENCE_REMEDIATION_PLAN.md §6.
//
// Two-tier cache for AI responses. Every Pro AI route checks the cache before
// hitting Claude; cache hits skip both the Claude call AND the AIBudgetTracker
// debit. This is the single biggest cost lever in the system per spec §5.5 #3.
//
// Storage tiers chosen per spec §6.1 table:
//   - Redis  for short-lived hot caches (TTL ≤ 24h, ephemeral OK)
//   - Postgres for long-lived results (≥ 1 week, inspectable via psql,
//                                       invalidation-driven)
//
// Caller never picks the storage tier — the typed `AICacheKey` declares its
// own backend so callers can't accidentally route a multi-day cache through
// Redis (where a flush would silently re-bill the user).

enum AICacheStorage {
    case redis
    case postgres
}

// MARK: - Typed cache keys
//
// One factory per spec §6.1 row. Adding a new AI feature in §7 means adding
// a new factory here, not inventing ad-hoc strings.

struct AICacheKey: Sendable {
    let value: String
    let storage: AICacheStorage
    let feature: String
    let ttl: TimeInterval

    // ── Implemented (Fix #3 ships these two) ──────

    static func weeklyReport(userId: String, weekStart: String) -> AICacheKey {
        AICacheKey(
            value: "insight:weekly:\(userId):\(weekStart)",
            storage: .postgres,
            feature: "weekly_report",
            // Spec §6.1: 7 days soft, forever hard. We use 7 days here and
            // rely on explicit invalidation (workout webhook, force_regenerate)
            // to handle the "hard" case earlier.
            ttl: 7 * 24 * 3600
        )
    }

    static func patternDetection(userId: String, totalDays: Int) -> AICacheKey {
        AICacheKey(
            value: "insight:pattern:\(userId):\(totalDays)",
            storage: .redis,
            feature: "pattern_detection",
            // Spec §6.1: 24h per correlation. Single-blob keying here; per-
            // correlation invalidation deferred until the pattern engine
            // supports targeted correlation queries.
            ttl: 24 * 3600
        )
    }

    // ── Stubbed (§7 features will fill these in) ──

    static func trainingProgram(userId: String, weekStart: String) -> AICacheKey {
        AICacheKey(
            value: "training:program:\(userId):\(weekStart)",
            storage: .postgres,
            feature: "training_program",
            // Spec §6.1: invalidated when recovery delta > 15 points. We start
            // with a 7-day TTL; webhook handlers should invalidate earlier.
            ttl: 7 * 24 * 3600
        )
    }

    static func recoveryPrescription(userId: String, date: String) -> AICacheKey {
        AICacheKey(
            value: "prescription:\(userId):\(date)",
            storage: .redis,
            feature: "recovery_prescription",
            ttl: 12 * 3600
        )
    }

    static func morningBriefing(userId: String, date: String) -> AICacheKey {
        AICacheKey(
            value: "briefing:\(userId):\(date)",
            storage: .redis,
            feature: "morning_briefing",
            ttl: 24 * 3600
        )
    }

    static func notificationBatch(userId: String, batchStart: String) -> AICacheKey {
        AICacheKey(
            value: "notifications:\(userId):\(batchStart)",
            storage: .redis,
            feature: "notification_batch",
            ttl: 3 * 24 * 3600
        )
    }

    static func dashboardInsights(userId: String, dataHash: String) -> AICacheKey {
        AICacheKey(
            value: "dashboard:insights:\(userId):\(dataHash)",
            storage: .redis,
            feature: "dashboard_insights",
            // Spec §6.1: "until data changes". The dataHash in the key forces
            // a new entry when inputs change, so TTL is just a memory ceiling.
            ttl: 24 * 3600
        )
    }

    static func mealTiming(userId: String, date: String, mealIndex: Int) -> AICacheKey {
        AICacheKey(
            value: "meal:timing:\(userId):\(date):\(mealIndex)",
            storage: .redis,
            feature: "meal_timing",
            ttl: 2 * 3600
        )
    }

    static func studySchedule(userId: String, examId: String) -> AICacheKey {
        AICacheKey(
            value: "study:plan:\(userId):\(examId)",
            storage: .postgres,
            feature: "study_schedule",
            // Spec §6.1: "until exam date changes". TTL is a backstop.
            ttl: 30 * 24 * 3600
        )
    }

    static func achievementCopy(userId: String, achievementId: String) -> AICacheKey {
        AICacheKey(
            value: "achievement:\(userId):\(achievementId)",
            storage: .postgres,
            feature: "achievement_copy",
            // Spec §6.1: forever. We model "forever" as ten years.
            ttl: 10 * 365 * 24 * 3600
        )
    }
}

// MARK: - Cache result

enum AICacheLookup<Value: Codable & Sendable>: Sendable {
    /// Cache hit, within TTL. Return immediately, no regeneration.
    case fresh(Value)
    /// Cache hit, past TTL but still readable. Return immediately;
    /// caller should trigger async regeneration via withSWR.
    case stale(Value)
    /// No entry, generate synchronously.
    case miss
}

// MARK: - AICache service

struct AICache {
    static let shared = AICache()
    private init() {}

    // MARK: - Generic wrappers

    /// Synchronous cache-aside pattern. Returns cached value on hit, runs
    /// `generate` on miss and stores the result.
    func withCache<T: Codable & Sendable>(
        key: AICacheKey,
        on req: Request,
        bypass: Bool = false,
        generate: () async throws -> T
    ) async throws -> (value: T, fromCache: Bool) {
        if !bypass {
            if let hit: T = try await lookup(key: key, on: req).fresh {
                return (hit, true)
            }
        }
        let fresh = try await generate()
        try await store(key: key, value: fresh, on: req)
        return (fresh, false)
    }

    /// Stale-while-revalidate. Returns cached value (fresh OR stale) when
    /// available and spawns a background regeneration on stale hits. Only
    /// blocks on Claude when the cache is fully empty.
    ///
    /// `generate` MUST be safe to run concurrently with the caller's flow:
    /// it runs in a detached Task and updates the cache for the next request.
    func withSWR<T: Codable & Sendable>(
        key: AICacheKey,
        on req: Request,
        bypass: Bool = false,
        generate: @Sendable @escaping () async throws -> T
    ) async throws -> (value: T, fromCache: Bool) {
        if bypass {
            let fresh = try await generate()
            try await store(key: key, value: fresh, on: req)
            return (fresh, false)
        }

        switch try await lookup(key: key, on: req) as AICacheLookup<T> {
        case let .fresh(value):
            return (value, true)
        case let .stale(value):
            // Return stale immediately; refresh in the background.
            // Per spec §6.2.
            spawnBackgroundRefresh(key: key, on: req, generate: generate)
            return (value, true)
        case .miss:
            let fresh = try await generate()
            try await store(key: key, value: fresh, on: req)
            return (fresh, false)
        }
    }

    // MARK: - Direct API (for callers that need finer control)

    func lookup<T: Codable & Sendable>(
        key: AICacheKey,
        on req: Request
    ) async throws -> AICacheLookup<T> {
        switch key.storage {
        case .redis:
            return try await lookupRedis(key: key, on: req)
        case .postgres:
            return try await lookupPostgres(key: key, on: req)
        }
    }

    func store<T: Codable & Sendable>(
        key: AICacheKey,
        value: T,
        on req: Request
    ) async throws {
        switch key.storage {
        case .redis:
            try await storeRedis(key: key, value: value, on: req)
        case .postgres:
            try await storePostgres(key: key, value: value, on: req)
        }
    }

    /// Drop a single cache entry. Used by webhook handlers when source data
    /// invalidates a cached result.
    func invalidate(key: AICacheKey, on req: Request) async {
        switch key.storage {
        case .redis:
            _ = try? await req.redis.delete(RedisKey(key.value)).get()
        case .postgres:
            _ = try? await CachedAIResponse.query(on: req.db)
                .filter(\.$cacheKey == key.value)
                .delete()
        }
    }

    /// Drop all entries for a given feature + user. Use when a coarse signal
    /// invalidates everything (e.g. user manually clicks "regenerate all" in
    /// settings, or a data wipe). For Redis entries this requires a SCAN
    /// — expensive; prefer per-key invalidate when possible.
    func invalidateAllForUser(feature: String, userId: String, on req: Request) async {
        let prefix = "\(feature):\(userId):"
        _ = try? await CachedAIResponse.query(on: req.db)
            .filter(\.$feature == feature)
            .filter(\.$cacheKey ~~ prefix) // LIKE 'prefix%'
            .delete()
        // Redis: rely on natural TTL expiry. The wildcard delete pattern
        // requires SCAN + DEL which we'll add when a feature needs it.
        _ = prefix
    }

    // MARK: - Background regeneration

    private func spawnBackgroundRefresh<T: Codable & Sendable>(
        key: AICacheKey,
        on req: Request,
        generate: @Sendable @escaping () async throws -> T
    ) {
        // Detach the regen from the request's task tree so the response can
        // finish without waiting for the new Claude call. The new context
        // uses `req.application` (long-lived) so DB/Redis stay reachable.
        let app = req.application
        let logger = req.logger
        let feature = key.feature
        let cacheValue = key.value
        Task.detached {
            do {
                let fresh = try await generate()
                let bgRequest = Request(application: app, on: app.eventLoopGroup.next())
                try await AICache.shared.store(key: key, value: fresh, on: bgRequest)
                logger.info("[ai_cache:\(feature)] SWR refresh ok key=\(cacheValue)")
            } catch {
                logger.warning("[ai_cache:\(feature)] SWR refresh failed key=\(cacheValue) err=\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Redis backend

    private func lookupRedis<T: Codable & Sendable>(
        key: AICacheKey,
        on req: Request
    ) async throws -> AICacheLookup<T> {
        let redisKey = RedisKey(key.value)
        guard let data = try await req.redis.get(redisKey, as: Data.self).get() else {
            return .miss
        }
        let payload = try JSONDecoder().decode(RedisCachePayload<T>.self, from: data)
        // We persist storedAt + ttl inside the payload so we can distinguish
        // fresh from stale within a single Redis TTL window. Redis's own
        // expiry removes the entry entirely (treated as miss).
        let age = Date().timeIntervalSince(payload.storedAt)
        if age <= key.ttl {
            return .fresh(payload.value)
        } else {
            return .stale(payload.value)
        }
    }

    private func storeRedis<T: Codable & Sendable>(
        key: AICacheKey,
        value: T,
        on req: Request
    ) async throws {
        let payload = RedisCachePayload(value: value, storedAt: Date(), ttl: key.ttl)
        let data = try JSONEncoder().encode(payload)
        // Hold the entry for 2x its logical TTL so SWR can serve stale.
        let redisTTLSeconds = Int(key.ttl * 2)
        try await req.redis
            .setex(RedisKey(key.value), to: data, expirationInSeconds: redisTTLSeconds)
            .get()
    }

    // MARK: - Postgres backend

    private func lookupPostgres<T: Codable & Sendable>(
        key: AICacheKey,
        on req: Request
    ) async throws -> AICacheLookup<T> {
        guard
            let row = try await CachedAIResponse.query(on: req.db)
                .filter(\.$cacheKey == key.value)
                .first()
        else {
            return .miss
        }
        let value = try JSONDecoder().decode(T.self, from: Data(row.payload.utf8))
        if row.expiresAt > Date() {
            return .fresh(value)
        } else {
            return .stale(value)
        }
    }

    private func storePostgres<T: Codable & Sendable>(
        key: AICacheKey,
        value: T,
        on req: Request
    ) async throws {
        let payloadData = try JSONEncoder().encode(value)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"
        let now = Date()
        let expiresAt = now.addingTimeInterval(key.ttl)

        if let existing = try await CachedAIResponse.query(on: req.db)
            .filter(\.$cacheKey == key.value)
            .first()
        {
            existing.payload = payloadString
            existing.generatedAt = now
            existing.expiresAt = expiresAt
            try await existing.save(on: req.db)
        } else {
            let row = CachedAIResponse(
                feature: key.feature,
                cacheKey: key.value,
                payload: payloadString,
                generatedAt: now,
                expiresAt: expiresAt
            )
            try await row.create(on: req.db)
        }
    }
}

// MARK: - Sugar

private extension AICacheLookup {
    /// Returns the value only on a fresh hit. Used by `withCache` (non-SWR)
    /// where stale is treated the same as miss.
    var fresh: Value? {
        if case let .fresh(value) = self { return value }
        return nil
    }
}

// MARK: - Wire payload (Redis only)

private struct RedisCachePayload<T: Codable>: Codable {
    let value: T
    let storedAt: Date
    let ttl: TimeInterval
}
