import Vapor
import Fluent
@preconcurrency import Redis

// MARK: - Whoop Data Controller
// Per BACKEND_API.md Sections 5.6-5.9 — Proxy endpoints for Whoop data.
// GET  /v1/whoop/recovery   — Recovery scores
// GET  /v1/whoop/sleep      — Sleep data
// GET  /v1/whoop/workouts   — Workout data
// GET  /v1/whoop/cycles     — Cycle/strain data

struct WhoopDataController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("recovery", use: getRecovery)
        routes.get("sleep", use: getSleep)
        routes.get("workouts", use: getWorkouts)
        routes.get("cycles", use: getCycles)
    }

    // MARK: - Cache TTL
    // Per BACKEND_API.md — Redis 120s TTL for data endpoints.
    private static let cacheTTL: Int = 120

    // MARK: - GET /recovery
    // Per BACKEND_API.md Section 5.6

    func getRecovery(_ req: Request) async throws -> Envelope<[WhoopRecoveryDTO]> {
        let userID = try req.auth.requireUserID()
        let query = try req.query.decode(WhoopDateQuery.self)
        let (startDate, endDate) = resolveDateRange(query)

        // Check Redis cache
        let cacheKey = RedisKey("whoop:\(userID):recovery:\(startDate):\(endDate)")
        if let cached = try await req.redis.get(cacheKey, as: String.self).get(),
           let data = cached.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let records = try? decoder.decode([WhoopRecoveryDTO].self, from: data) {
                req.logger.info("Whoop cache hit: recovery for \(userID)")
                return Envelope(data: records, requestID: req.requestID)
            }
        }

        // Fetch from Whoop API
        let response = try await WhoopAPIService.shared.fetchRecovery(
            for: userID,
            startDate: startDate,
            endDate: endDate,
            on: req
        )

        let records = response.records.map { WhoopRecoveryDTO(from: $0) }

        // Cache in Redis
        try await cacheResponse(records, key: cacheKey, on: req)

        return Envelope(data: records, requestID: req.requestID)
    }

    // MARK: - GET /sleep
    // Per BACKEND_API.md Section 5.7

    func getSleep(_ req: Request) async throws -> Envelope<[WhoopSleepDTO]> {
        let userID = try req.auth.requireUserID()
        let query = try req.query.decode(WhoopDateQuery.self)
        let (startDate, endDate) = resolveDateRange(query)

        let cacheKey = RedisKey("whoop:\(userID):sleep:\(startDate):\(endDate)")
        if let cached = try await req.redis.get(cacheKey, as: String.self).get(),
           let data = cached.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let records = try? decoder.decode([WhoopSleepDTO].self, from: data) {
                req.logger.info("Whoop cache hit: sleep for \(userID)")
                return Envelope(data: records, requestID: req.requestID)
            }
        }

        let response = try await WhoopAPIService.shared.fetchSleep(
            for: userID,
            startDate: startDate,
            endDate: endDate,
            on: req
        )

        let records = response.records.map { WhoopSleepDTO(from: $0) }
        try await cacheResponse(records, key: cacheKey, on: req)

        return Envelope(data: records, requestID: req.requestID)
    }

    // MARK: - GET /workouts
    // Per BACKEND_API.md Section 5.8

    func getWorkouts(_ req: Request) async throws -> Envelope<[WhoopWorkoutDTO]> {
        let userID = try req.auth.requireUserID()
        let query = try req.query.decode(WhoopDateQuery.self)
        let (startDate, endDate) = resolveDateRange(query)

        let cacheKey = RedisKey("whoop:\(userID):workouts:\(startDate):\(endDate)")
        if let cached = try await req.redis.get(cacheKey, as: String.self).get(),
           let data = cached.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let records = try? decoder.decode([WhoopWorkoutDTO].self, from: data) {
                req.logger.info("Whoop cache hit: workouts for \(userID)")
                return Envelope(data: records, requestID: req.requestID)
            }
        }

        let response = try await WhoopAPIService.shared.fetchWorkouts(
            for: userID,
            startDate: startDate,
            endDate: endDate,
            on: req
        )

        let records = response.records.map { WhoopWorkoutDTO(from: $0) }
        try await cacheResponse(records, key: cacheKey, on: req)

        return Envelope(data: records, requestID: req.requestID)
    }

    // MARK: - GET /cycles
    // Per BACKEND_API.md Section 5.9

    func getCycles(_ req: Request) async throws -> Envelope<[WhoopCycleDTO]> {
        let userID = try req.auth.requireUserID()
        let query = try req.query.decode(WhoopDateQuery.self)
        let (startDate, endDate) = resolveDateRange(query)

        let cacheKey = RedisKey("whoop:\(userID):cycles:\(startDate):\(endDate)")
        if let cached = try await req.redis.get(cacheKey, as: String.self).get(),
           let data = cached.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let records = try? decoder.decode([WhoopCycleDTO].self, from: data) {
                req.logger.info("Whoop cache hit: cycles for \(userID)")
                return Envelope(data: records, requestID: req.requestID)
            }
        }

        let response = try await WhoopAPIService.shared.fetchCycles(
            for: userID,
            startDate: startDate,
            endDate: endDate,
            on: req
        )

        let records = response.records.map { WhoopCycleDTO(from: $0) }
        try await cacheResponse(records, key: cacheKey, on: req)

        return Envelope(data: records, requestID: req.requestID)
    }

    // MARK: - Helpers

    /// Resolve date range from query params. Defaults to today if no dates provided.
    private func resolveDateRange(_ query: WhoopDateQuery) -> (String, String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        if let date = query.date {
            return (date, date)
        }

        let start = query.startDate ?? today
        let end = query.endDate ?? today
        return (start, end)
    }

    /// Cache an Encodable response in Redis with TTL.
    private func cacheResponse<T: Encodable>(_ data: T, key: RedisKey, on req: Request) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(data)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            _ = try await req.redis.setex(key, to: jsonString, expirationInSeconds: Self.cacheTTL).get()
        }
    }
}

// MARK: - Request Extension for Request ID

extension Request {
    /// Get the request ID from storage (set by RequestIdMiddleware).
    var requestID: String? {
        storage[RequestIDKey.self]
    }
}
